#!/bin/bash

## PiHERALD CLIENT SOFTWARE SUITE
## VERSION: 0.1
## (C): Nicholas Card, 2016
##
## piherald-client-update.sh
#
# This script updates the PiHerald client software.
#
# This script does the following:
#	(1) Reads the piherald-client.ini config file.
#	(2) Connects to the PiHerald server.
#	(3) Downloads the PiHerald client files.
#	(4) Checks permissions for the downloaded files, and copies/installs
#		all files in the appropriate locations as needed.
#	(5) Disconnects from the PiHerald server.
#
# IMPORTANT:
#
# This script should not be called if PiHerald is running.  As of this version,
# the updater does not check if this condition is met.  If PiHerald is running
# when this updater runs, it may result in an unstable configuration.  In
# theory, this deficiency should not be permanent.
#

logfile=/tmp/piherald-client-update.log
touch $logfile

# If called with the selfupdate flag, remove the old update script and replace it.
if [[ $1 == "selfupdate" ]]; then
	sleep 1 # sleep one second to make sure original script has exited
	rm -f /opt/piherald/piherald-client-update.sh
	script=$(realpath $0)
	sudo install --group=piherald --owner=piherald --mode=770 $script /opt/piherald/piherald-client-update.sh
	rm $script
	exit
fi

# If called with the piherald-client flag, remove the old script and replace it
if [[ $1 == "piherald-client" ]]; then
	sleep 1 # sleep one second to make sure original script has exited
	rm -f /opt/piherald/piherald-client.sh
	script=/opt/piherald/piherald-client.sh.tmp
	sudo install --group=piherald --owner=piherald --mode=770 $script /opt/piherald/piherald-client.sh
	rm $script
	exit
fi

### UPDATE RASPBERRY PI ###
# (And do a few other things too)

#If called with "coresoftware" or no flag, run core softeware update
if [[ $1 == "coresoftware" || $1 == "" ]]; then

	#Update repos and upgrade existing software
	echo "Updating Repos and upgrading existing software..." >> $logfile
	echo "Updating Repos and upgrading existing software (this may take a while)..."
	sudo apt-get -y -q update >> $logfile
	sudo apt-get -y -q upgrade >> $logfile
	sudo apt-get -y -q dist-upgrade >> $logfile
	echo "Done."

	### INSTALL PROGRAMS ###

	#Install programs for PiHerald
	echo "Installing programs for PiHerald..." >> $logfile
	echo "Install programs for PiHerald (this may take a while)..."
	sudo apt-get -y -q install xtightvncviewer >> $logfile
	sudo apt-get -y -q install nmap >> $logfile
	sudo apt-get -y -q install unclutter >> $logfile
	echo "Done."

	# Clean up install
	echo "Cleaning up install" >> $logfile
	echo "Cleaning up install..."
	sudo apt-get -y -q autoremove >> $logfile
	sudo apt-get -y -q clean >> $logfile
	echo "Done."

	# Install Perl modules
	echo "Installing Perl Modules..."
	echo "Installing Perl Modules" >> $logfile
	sudo /bin/bash -c "export PERL_MM_USE_DEFAULT=1; cpan App::cpanminus" >> $logfile
	sudo cpanm Config::IniFiles >> $logfile
	echo "Done."
	
fi # end coresoftware update

### GET PiHERALD FILES ###

#If called with "piherald" or no flag, run piherald update
if [[ $1 == "piherald" || $1 == "" ]]; then

	echo "Getting PiHerald Files..."
	echo "Getting PiHerald Files" >> $logfile
	domain=`dnsdomainname`
	sudo mount piherald.$domain:/piherald /mnt >> $logfile

	# Make the directory for the PiHerald Files
	echo "Make directory..."
	sudo mkdir -p /opt/piherald >> $logfile

	# Copy over the files
	echo "Copying over the files..."
	sudo install --group=piherald --owner=piherald --mode=775 /mnt/piherald-client.sh /opt/piherald/piherald-client.sh.tmp
	sudo install --group=piherald --owner=piherald --mode=770 /mnt/piherald-client-update.sh /opt/piherald/piherald-client-update.sh.tmp
	sudo install --group=piherald --owner=piherald --mode=770 /mnt/piherald-client-vncviewer.sh /opt/piherald/piherald-client-vncviewer.sh
	sudo install --group=piherald --owner=piherald --mode=770 /mnt/piherald-client-locales.sh /opt/piherald/piherald-client-locales.sh
	sudo install --group=piherald --owner=piherald --mode=770 /mnt/piherald-client-network.sh /opt/piherald/piherald-client-network.sh
	sudo install --group=piherald --owner=piherald --mode=770 /mnt/piherald-client-comm.pl /opt/piherald/piherald-client-comm.pl
	
	sudo install --group=piherald --owner=root --mode=4750 /mnt/piherald-client-tvservice.sh /opt/piherald/piherald-client-tvservice.sh

	sudo install --group=piherald --owner=piherald --mode=664 /mnt/vncviewer.desktop /opt/piherald/vncviewer.desktop

	sudo install --group=piherald --owner=piherald --mode=664 /mnt/piherald-server.pub /opt/piherald/piherald-server.pub

	sudo umount /mnt >> $logfile

	### INSTALL FILES ###

	# CP startup file to PiHerald user account
	sudo mkdir -p /home/piherald/.config/autostart/
	sudo cp /opt/piherald/vncviewer.desktop /home/piherald/.config/autostart/

	sudo chown -R piherald:piherald /home/piherald/.config

	### SETUP SSH KEY ###
	sudo mkdir -p /home/piherald-admin/.ssh
	sudo touch /home/piherald-admin/.ssh/authorized_keys
	sudo chown piherald-admin:piherald-admin -R /home/piherald-admin/

	#check if key is already in authorized_keys
	grep -q "$(cat /opt/piherald/piherald-server.pub)" /home/piherald-admin/.ssh/authorized_keys
	grepexitcode=$?

	if [[ $grepexitcode -eq 1 ]]; then
		# current key does not exist in authorized keys
		cat /opt/piherald/piherald-server.pub >> /home/piherald-admin/.ssh/authorized_keys
	fi

	### GET STARTING CONFIG FILE ###

	# If the config file doesn't exist, download config file from setup drive
	if [ ! -e /opt/piherald/piherald-client.ini ]; then
		echo "Getting config file..."
		echo "Getting config file" >> $logfile
		domain=`dnsdomainname`
		sudo mount piherald.$domain:/piherald-setup /mnt >> $logfile
		sudo install --group=piherald --owner=piherald --mode=660 /mnt/piherald-client.ini /opt/piherald/piherald-client.ini
		sudo umount /mnt
	fi

	### GET STARTING PASSWD FILE ###

	# If the passwd file doesn't exist, download it from setup drive
	if [ ! -e /opt/piherald/vncpasswd ]; then
		echo "Getting passwd file..."
		echo "Getting passwd file" >> $logfile
		domain=`dnsdomainname`
		sudo mount piherald.$domain:/piherald-setup /mnt >> $logfile
		sudo install --group=piherald --owner=piherald --mode=660 /mnt/vncpasswd /opt/piherald/vncpasswd
		sudo umount /mnt
	fi

fi #end piherald update

### UPDATE UPDATER ###

#Lastly, we tell the new updater to update itself.
/opt/piherald/piherald-client-update.sh.tmp selfupdate &
