#!/usr/bin/perl

my %CONFIG;

# Note this function is GPL licensed
# we'll take this out soon, though.
# stolen, er.. borrowed from xen-shell
sub parseConfigurationFile
{
    my ($file) = (@_);

    #
    #  Make sure the file is specified + exists.
    #
    return if ( !-e $file );

    open( FILE, "<", $file ) or die "Cannot read file '$file' - $!";
    while ( defined( my $line = <FILE> ) )
    {
        chomp $line;

        # Skip lines beginning with comments
        next if ( $line =~ /^([ \t]*)\#/ );

        # Skip blank lines
        next if ( length($line) < 1 );

        # Strip trailing comments.
        if ( $line =~ /(.*)\#(.*)/ )
        {
            $line = $1;
        }

        # Find variable settings
        if ( $line =~ /([^=]+)=([^\n]+)/ )
        {
            my $key = $1;
            my $val = $2;

            # Strip leading and trailing whitespace.
            $key =~ s/^\s+//;
            $key =~ s/\s+$//;
            $val =~ s/^\s+//;
            $val =~ s/\s+$//;

            # Store value.
            $CONFIG{ $key } = $val;
        }
    }
    close(FILE);
}

#
#  Parse our configuration file, if it exists.
#
$CONFIG{ 'config' }    = '/etc/xen-shell/xen-shell.conf';
parseConfigurationFile( $CONFIG{ 'config' } ) or die 'No config';

use Carp;
require DBI;
use Data::Dumper;

# Data storage
use Data::UUID;

require RPC::XML::Server;
require RPC::XML::Procedure;

BEGIN { push @INC,'/root/cloud/lib/'; }
require Annelidous::Frontend;
require Annelidous::Search::Ubersmith;

#
# UUID generation
#
my $uuidlib = Data::UUID->new();

#
# Annelidous
#
my $anneSearch=$CONFIG{'annelidous-search-module'}->new(
	-dbh=>DBI->connect(
	"DBI:".$CONFIG{'annelidous-search-dbdriver'}.":".
	"host=".$CONFIG{'annelidous-search-dbhost'}.";".
	"database=".$CONFIG{'annelidous-search-dbname'}.";",
	$CONFIG{'annelidous-search-dbuser'},
	$CONFIG{'annelidous-search-dbpass'}
));
my $annelidous=Annelidous::Frontend->new(
    -search_module=>$anneSearch,
    -connector_module=>$CONFIG{'annelidous-connector-module'}
);

#
# Methods
#

# TODO: Memoize
#use Tie::Hash;
#use Memoize;
#use Memoize::Expire;
#use DB_File;
#tie my %disk_cache, 'DB_File', '/tmp/xmlrpc.cache', O_CREAT|O_RDWR, 0666;
#tie my %cache => 'Memoize::Expire', 
#	  	     LIFETIME => '10',    # In seconds
#			 HASH => \%disk_cache;
##memoize 'gcstore', SCALAR_CACHE => [ HASH => \%cache ];
##memoize 'unstore', SCALAR_CACHE => [ HASH => \%cache ];

# store of the actual objections.
# we store here because we cannot serialize our objects due to XS.
# we use memoize to expire keys, which is hooked into a deletion method
# to GC this hash.
my $hashstore={};

# Store the serialized object into redis.
# We're using redis because it lets us expire this stuff
# after a certain amount of time. Existing perl modules do this too
# but redis is more scalable.
sub store {
	my $uuid=$uuidlib->create_str();

	# Store the object.
	if (ref($_[0]) eq "ARRAY") {
		$hashstore->{ $uuid }=\@_;
	} else {
		$hashstore->{ $uuid }=shift;
	}
	return $uuid;
}

# Take the uuid argument, fetch from redis, thaw, return.
sub unstore {
	my $uuid=shift;
	return $hashstore->{$uuid};
}

#
# Main
#

my $rpcs = RPC::XML::Server->new(port => $CONFIG{'annelidous-frontend-xmlrpc-port'});

# User login
$rpcs->add_method({
	name => 'user.authenticate',
	code => sub {
		my $self=shift;
		my $user=shift;
		my $pass=shift;
		my @r=$annelidous->search->auth_account($user,$pass);
		unless (@r) {
			return 0;
		}
		# this is a ukey
		return store \@r;
	},
	signature => [ 'string string string', 'string int string' ]
});

# Get services
$rpcs->add_method({
	name => 'user.list_vm',
	code => sub {
		my $self=shift;
		my $ukey=shift;
		return unstore $ukey;
	},
	signature => [ 'array string' ]
});

# VM creation 
$rpcs->add_method({
	name => 'vm.new',
	code => sub {
		my $self=shift;
		my $ukey=shift;
		my $id=shift;
		foreach my $i (@{${unstore $ukey}[0]}) {
			# I.E. if user is authorized...
			#warn "$i =?= $id";
			if ($i == $id) {
				return store ( $annelidous->new_vm($i) );
			}
			# else {
			#	warn "$i != $id";
			#}
		}
		return 0;
	},
	signature => [ 'string string string', 'string string int' ]
});

# Connector creation 
$rpcs->add_method({
	name => 'connector.new',
	code => sub {
		my $self=shift;
		my $vm=unstore shift;
		return store $annelidous->new_connector($vm);
	},
	signature => [ 'string string' ]
});

# Rescue
$rpcs->add_method({
	name => 'connector.rescue',
	code => sub {
		my $self=shift;
		my $conn=unstore shift;
		return $conn->rescue();
	},
	signature => [ 'boolean string' ]
});

# Boot
$rpcs->add_method({
	name => 'connector.boot',
	code => sub {
		my $self=shift;
		my $conn=unstore shift;
		return $conn->boot();
	},
	signature => [ 'boolean string' ]
});

# Shutdown
$rpcs->add_method({
	name => 'connector.shutdown',
	code => sub {
		my $self=shift;
		my $conn=unstore shift;
		return $conn->shutdown();
	},
	signature => [ 'boolean string' ]
});

# Uptime 
$rpcs->add_method({
	name => 'connector.uptime',
	code => sub {
		my $self=shift;
		my $conn=unstore shift;
		return $conn->uptime();
	},
	signature => [ 'string string' ]
});

# Status
$rpcs->add_method({
	name => 'connector.status',
	code => sub {
		my $self=shift;
		my $conn=unstore shift;
		return $conn->status();
	},
	signature => [ 'boolean string' ]
});

# Destroy
$rpcs->add_method({
	name => 'connector.destroy',
	code => sub {
		my $self=shift;
		my $conn=unstore shift;
		return $conn->destroy();
	},
	signature => [ 'boolean string' ]
});

$rpcs->server_loop; # Never returns

1;
