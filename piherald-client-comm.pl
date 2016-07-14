#!/usr/bin/env perl

## PiHERALD CLIENT SOFTWARE SUITE
## VERSION: 0.1
## (C): Nicholas Card, 2016
##
## piherald-client-comm.pl
#
# This script is used to communicate with the PiHerald Server as well as manage
# the client PiHerald configuration file.
#
# The message the script sends is:
#		<uuid from config>,<current IP>,<hostname from config>,<cur. resx>,<cur. resy>
#
# This script is intended to be used indirectly through piherald-client.sh.
#
#	piherald-client-comm.pl - sends msg to server 
#

use strict;
use warnings;
use English;
use Config::IniFiles;
use IO::Socket::SSL;

my ($action) = @ARGV;
my $configfile = "/opt/piherald/piherald-client.ini";

chomp(my $ip = `ip addr | grep -Eo 'inet ([0-9]{1,3}\.){3}[0-9]{1,3}' | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | grep -Ev '127\.([0-9]{1,3}\.){2}[0-9]{1,3}'`);

chomp(my $resx=`sudo tvservice -s | grep -Po '[0-9]{3,}x[0-9]{3,}' | grep -Po '[0-9]+(?=x)'`);
chomp(my $resy=`sudo tvservice -s | grep -Po '[0-9]{3,}x[0-9]{3,}' | grep -Po '(?<=x)[0-9]+'`);

my $ini = Config::IniFiles->new( -file => "$configfile" );
my $uuid = $ini->val('piheraldclient','uuid');
my $hostname = $ini->val('piheraldclient','hostname');

my $domain = $ini->val('piheraldserver','domain');
my $server = $ini->val('piheraldserver','hostname');
my $port = $ini->val('piheraldserver','port');

my $msg = "$uuid,$ip,$hostname,$resx,$resy";
my $socket;

# flush after every write
$| = 1;

# Try establishing the socket 5 times
for (my $i=1; $i <= 5; $i++) {
	$socket = IO::Socket::SSL->new(
		PeerAddr=> "$server.$domain:$port",
		Proto => 'tcp',
		SSL_verify_mode => 0,
	) or do {
		print "Error, unable to connect to '$server.$domain:$port', attempt $i\n";
		sleep 5;
		if ($i eq 5) {
			die "Unable to connect to '$server.$domain:$port', $SSL_ERROR";
		} else {
			#If we haven't tried 5 times yet, go to the next try.
			next;
		}
	};
	
	#If we are here, the connection was successful, so this is our last loop
	last;
}

print "TCP Connection Success.\n";

# write on the socket to server.
print $socket "$msg\n";

$socket->close();
