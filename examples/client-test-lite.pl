#!/usr/bin/perl
# Copyright 2009  GrokThis.net Internet Solutions <support@grokthis.net>
# Copyright 2009  Eric Windisch <eric@grokthis.net>
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
# OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
# IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
# NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
# THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
# 

use XMLRPC::Lite +trace=>[qw(transport debug)];
use Data::Dumper;

my $cli = XMLRPC::Lite->proxy('https://secure.grokthis.net/manage/vps/rpc/');

# List methods.
my $resp;

my $username="";
my $password="";
my $serviceNum="";

$resp = $cli->call('system.listMethods');
print Dumper $resp->result;

# Build a vm
$resp = $cli->call('user.authenticate',$username,$password);
my $auth=$resp->result;
print Dumper $auth;

# Build a vm
$resp = $cli->call('user.list_vm',$auth);
my @machines=$resp->result;
print Dumper @machines;

foreach my $vm (@machines) {
	# Build a vm
	$resp = $cli->call('vm.new',$auth,$vm);
	my $vm=$resp->result;
	print Dumper $vm;

	# Build a connector (connect to the server)
	$resp = $cli->call('connector.new',$vm);
	my $conn=$resp->result;
	print Dumper $conn;

	# Get uptime
	$resp = $cli->call('connector.uptime',$conn);
	print Dumper $resp->result;

	# Get status
	$resp = $cli->call('connector.status',$conn);
	print Dumper $resp->result;

	# Initiate boot
	$resp = $cli->call('connector.boot',$conn);
	print Dumper $resp->result;

	# Initiate shutdown
	$resp = $cli->call('connector.shutdown',$conn);
	print Dumper $resp->result;

	print "Sleeping to give the service time to shutdown...\n";
	sleep 30;

	# Initiate forced shutdown (aka destroy)
	$resp = $cli->call('connector.destroy',$conn);
	print Dumper $resp->result;
}
