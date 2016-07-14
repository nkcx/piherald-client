#!/bin/bash

## PiHERALD CLIENT SOFTWARE SUITE
## VERSION: 0.1
## (C): Nicholas Card, 2016
##
## piherald-client.sh
#
# This script manages the PiHerald client software.
#
# This script is intended to receive commands from the PiHerald Server and
# manipulate the PiHerald Client software appropriate.  This script responds to
# the following commands:
#
#	piherald-client start	- launches vncviewer (piherald-client-vncviewer.sh)
#	piherald-client stop	- stops vncviewer
#	piherald-client restart	- stops and then launches vncviewer
#	piherald-client update	- stops vncviewer, runs update (piherald-client-update.sh), and starts vncviewer
#	piherald-client message	- sends message to PiHerald Server
#
# There are also the following update commands:
#
#	piherald-client update locales	- stops vncviewer, runs locales update (piherald-client-locales.sh), runs update, and starts vncviewer
#	piherald-client update network	- stops vncviewer, runs network update (piherald-client-network.sh), runs update, and starts vncviewer
#	piherald-client update update	- stops vncviewer, runs update twice, starts vncviewer (this is needed if piherald-client-update.sh) is updated
#
# IMPORTANT:
#
# This script is meant to be run by a user (such as piherald-admin) who has sudo permissions.
#

piheralduser=piherald
display=:0
exitcode=0
vncpidfile=/home/piherald/.piherald-client-vncviewer.pid

runaspiherald=0

updateneeded=0
running=0

piheralddir=/opt/piherald
vncviewer=piherald-client-vncviewer.sh
update=piherald-client-update.sh
locales=piherald-client-locales.sh
network=piherald-client-network.sh

# Create subfunctions

# Check if user has sudo ability:
if [[ $USER == $piheralduser ]]; then
	runaspiherald=1
elif ! sudo -n true; then
	echo "ERR: User does not have password-less sudo ability.  Please run as user with sudo access."
	exit 1
fi

function start-vncviewer {
	if [[ -e $vncpidfile && $1 != "force" ]]; then
		echo "VNC Viewer already runnning."
		echo "Use '$0 start force' to force start the VNC Viewer."
		exitcode=3
	else 	
		echo "Starting VNC Viewer..."
		if [[ $runaspiherald -eq 1 ]]; then
			#echo "Piherald User!"
			/bin/bash -c "export DISPLAY=$display; $piheralddir/$vncviewer" &>/dev/null &
		else
			#echo "Not piherald user!"
			sudo -u $piheralduser /bin/bash -c "export DISPLAY=$display; $piheralddir/$vncviewer" &>/dev/null &
		fi
		send-message
		echo "Done."
		exitcode=0
	fi
}

function stop-vncviewer {
	if [[ -e $vncpidfile ]]; then
		echo "Stopping VNC Viewer..."
		sudo kill `cat $vncpidfile` &>/dev/null &
		echo "Done."
		exitcode=0
		running=1
	else
		echo "VNC Viewer not running."
		exitcode=3
	fi
}

function status-vncviewer {
	if [[ -e $vncpidfile ]]; then
		# Might be running, check processes
		if ps -p `cat $vncpidfile` >/dev/null; then
			# process exists
			echo "VNC Viewer running."
			exitcode=0
		else
			# process does not exist
			echo "PID file exists, but VNC Viewer not running."
			exitcode=4
		fi
	else
		echo "VNC Viewer stopped."
		exitcode=3
	fi
}

function send-message {
	perl /opt/piherald/piherald-client-comm.pl
}

function usage {
	echo $"Usage: $0 {start|stop|restart|message|update[ update|locales|network]}"
}


function run-update {
	# Updating is more complicated than it might seem.  One problem that we
	# face is that we have to close this script to update it. The way
	# we handle this is as follows:
	#	- Run the updater script.
	#	- Set update=1 flag
	#	- On piherald-client exit, perform update.
	echo "Updating PiHerald..."
	$piheralddir/$update $1
	updateneeded=1
	echo "Done."
	exitcode=0
}

function run-locales {
	echo "Updating locales..."
	$piheralddir/$locales
	echo "Done."
	exitcode=0
}

function run-network {
	echo "Updating network..."
	$piheralddir/$network
	echo "Done."
	exitcode=0
}

if [[ $runaspiherald -eq 1 && $1 == "start" ]]; then
	start-vncviewer
elif [[ $runaspiherald -eq 1 ]]; then
	echo "User $piheralduser can only use 'start' function"
	usage
else
# Get input
case "$1" in
    start)
        start-vncviewer $2
        ;;
    stop)  
		stop-vncviewer
        ;;
    status)
		status-vncviewer
		;;
	restart)  
		stop-vncviewer
		start-vncviewer
        ;;
	message)  
		send-message
        ;;
    update)  
		case "$2" in
			"")
				stop-vncviewer
				run-update
				if [[ $running -eq 1 ]]; then start-vncviewer; fi
				;;
			update)
				stop-vncviewer
				run-update
				run-update piherald
				if [[ $running -eq 1 ]]; then start-vncviewer; fi
				;;
			locales)
				stop-vncviewer
				run-locales
				run-update
				if [[ $running -eq 1 ]]; then start-vncviewer; fi
				;;
			network)
				stop-vncviewer
				run-network
				run-update
				if [[ $running -eq 1 ]]; then start-vncviewer; fi
				;;
			*)
				usage
				exit 1
		esac
        ;;
	*)
		usage
        exit 1
esac

fi # end user check

if [[ $updateneeded -eq 0 ]]; then
	#echo "Exiting like normal"
	exit $exitcode
else
	#echo "Exiting with update!"
	sleep 2
	$piheralddir/$update piherald-client &
	exit $exitcode
fi
