#!/bin/bash

## PiHERALD CLIENT SOFTWARE SUITE
## VERSION: 0.1
## (C): Nicholas Card, 2016
##
## piherald-client-vncviewer.sh
#
# This script manages the PiHerald client software.
#
# This script runs the VNC Viewer, and connects to the VNC server according to
# the configuration file.
#
# This script has the following flags:
#
#	-h/-? help
#	-c path to config file (default /opt/piherald/piherald-client.ini)
#	-p path to PID file (default $HOME/.startvnc.pid)
#	-u user that should be running file (default piherald)
#	   Use this option if you want to run this script as a different user.
#	-v VNC program to use (default vncviewer)
#
# IMPORTANT:
#
# Users should rarely need to call piherald-client-vncviewer.sh directly.  If the
# local system is configured correctly, piherald-client-vncviewer.sh should start
# automatically with the system.  Otherwise, it should be managed using the main
# piherald-client.sh script:
#	 piherald-client start   - starts pihearld-client-vncviewer.sh
#	 piherald-client stop    - stops piherald-client-vncviewer.sh
#	 piherald-client restart - restarts piherald-client-vncviewer.sh
#

#Set Exit Trap
function finish {
	kill -TERM $(jobs -p)
	rm -f $pidfile
	exit
}

trap 'finish' SIGINT SIGTERM KILL EXIT

# Show Help
function show_help {

echo "piherald-client-vncviewer.sh

Runs the VNC Viewer using settings based on the config file.
	-h/-? help
	-c path to config file (default /opt/piherald/piherald-client.ini)
	-p path to PID file (default $HOME/.startvnc.pid)
	-u user that should be running file (default piherald)
	   Use this option if you want to run this script as a different user.
	-v VNC program to use (default vncviewer)

In normal use, you should not need a command argument.

Users should rarely need to call piherald-client-vncviewer.sh directly.  If the
local system is configured correctly, piherald-client-vncviewer.sh should start
automatically with the system.  Otherwise, it should be managed using the main
piherald-client.sh script:
	piherald-client start   - starts pihearld-client-vncviewer.sh
	piherald-client stop    - stops piherald-client-vncviewer.sh
	piherald-client restart - restarts piherald-client-vncviewer.sh
"
}

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.

#Varibles
configfile='/opt/piherald/piherald-client.ini'
vncprogram='vncviewer'
user='piherald'
pidfile=$HOME'/.piherald-client-vncviewer.pid'

while getopts "h?cvup:" opt; do
    case "$opt" in
    h|\?)
        show_help
        exit 0
        ;;
    v)  vncprogram=$OPTARG
        ;;
    c)  configfile=$OPTARG
        ;;
    u)  user=$OPTARG
        ;;
    p)  pidfile=$OPTARG
        ;;
    esac
done

#Write PID file
echo "$$" > $pidfile

#Only run program if correct user
if [ "$(whoami)" != $user ]; then
   echo "This script must be run as user $user." 1>&2
   exit 1
fi

# Prevent Power Saving
xset s off -dpms

# Disable on-screen cursor
unclutter &

#Import Config File
echo "Importing Config File..."
while read line || [ -n "$line" ]; do
    if [[ $line =~ ^"["(.+)"]"$ ]]; then
        arrname=${BASH_REMATCH[1]}
        declare -A $arrname
    elif [[ $line =~ ^([_[:alpha:]][_[:alnum:]]*)"="(.*) ]]; then
        declare ${arrname}[${BASH_REMATCH[1]}]="${BASH_REMATCH[2]}"
    fi
done < $configfile

echo "Done."

## Main Loop ##

# First, we iterate over the servers
# Once we get a server we can ping, we try to connect to it.
# If we get disconnected, or are unable to connect, loop back to the top, and 
# try the next server, etc.
#

echo "Starting Main Loop..."

i=0

while true; do
	
	#Check if server is alive
	
	while true; do
		echo "Checking server $i..."
		hostnameref=server$i[hostname]
		hostname=${!hostnameref}
		displayref=server$i[display]
		display=${!displayref}
		passwdfileref=server$i[passwdfile]
		passwdfile=${!passwdfileref}
		
		echo "$hostname:$display ($passwdfile)"
		
		#If the variable is blank (aka, we've reached the end of our servers), then
		#we're done.
		if [[ $hostname == "" ]]; then
			i=0
			echo "ERROR: Unable to access any servers."
			exit 3
		fi
		
		# Try pinging each host 4 times, sleeping 1 second in between
		echo "Pinging host..."
		for j in {1..4}; do 
			ping -c 1 $hostname > /dev/null
			if [[ $? -eq 0 ]]; then
				#Ping is good
				#Break out of test loop and varset loop only if I can ping server
				echo "Ping successful!"
				
				#Now, check if we can access the display port on the server
				port=$(expr 5900 + $display)
				if nc -z $hostname $port; then
					echo "Port Open!"
					break 2
				else 
					echo "Port Closed!"
				fi
			fi
			sleep 1
		done
		
		# Add 1 to the index, to try the next server.
		i+=1
	done
	
	hostname=${server0[hostname]}
	display=${server0[display]}
	passwdfile=${server0[passwdfile]}
	
	# Run VNC Viewer command
	$vncprogram -fullscreen -viewonly -passwd $passwdfile $hostname:$display &
	wait
	sleep 10
done
