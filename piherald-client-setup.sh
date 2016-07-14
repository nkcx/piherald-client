#!/bin/bash

# This script walks you through the setup for a RaspberryPi to be used for
# PiHerald.  Hopefully, I'll be able to create a custom image that has all
# of this someday, but that day is not today.
#
# This script does the following:
#	(1) Prompts the user for network settings.
#	(2) Sets up network. (This section is modified from piherald-client-network.sh)
#	(3) Creates PiHerald users.
#	(4) Installs XFCE and LightDM packages.
#	(5) Establishes mount and gets piherald-client-*.sh files
#	(6) Installs PiHerald files, packages, and updates Pi. (Uses piherald-client-updates.sh)
#	(7) Configures packages.
#	(8) Update config and send msg to PiHerald Server
#
# The script makes a critical assumption about the setup:
#   -The image is based on Rasbian Jessie Lite
#
# The script also makes a few less than critical assumptions that only need to
# be met during setup, and can be changed later.
#	-The ethernet adapter is eth0
#	-The wireless adapter is wlan0
#	-All wireless networks the user wants to connect to are WPA[2]-PSK

clear

logfile=/tmp/piherald-client-setup.log
touch $logfile

### WELCOME ####
echo "PiHerald Install v0.5

Welcome to the PiHerald Installer!  This installer assumes that you are
running on a Jessie Rasbian Lite image from the RaspberryPi Foundation.

We are going to do the following.  Only step 1 requires any user intervention:
    1. Get network settings from user.
	2. Set up network based on network settings.
	3. Create and configure PiHerald users.
	4. Get initial PiHerald files from PiHerald Server.
	5. Runs \"piherald-client-update.sh\" to update client.
	6. Installs packages.
	7. Configures packages.

After the install completes, please reboot the Pi.
"

###############################################################################
## SECTION 01
##
## Prompt user for network settings.
##
## In this section, the user is prompted for network settings:
##	* Hostname
##	* Domain
##	* Network type (wired/wireless)
##		* If wireless, SSID and passkey
##	* Static/DHCP
##		* If static, IP, subnet, gateway, and DNS server(s)
##
## This section requires user input.  This may not be skipped in the current
## version, but hopefully a later version will have command line switches to
## skip this section.
#

echo "(1) Get network settings..." >> $logfile

echo "+++ (1) NETWORK SETTINGS +++

First, the installer is going to ask you a few questions about your network
setup:
"

#Keep running until user accepts results
while true; do

#Hostname
while true; do
	echo -n "Enter the hostname: "
	read hostname
	if [[ $hostname =~ ^[a-zA-Z0-9][-a-zA-Z0-9]{0,61}[a-zA-Z0-9]$ ]]; then
		break
	else
		echo -e "\e[1m\e[31mERR: \e[0mHostname must be 2-63 characters, and must only contain a-z, A-Z, and 0-9."
	fi
done

#Domain
while true; do
	echo -n "Enter the domain: "
	read domain
	if [[ $hostname.$domain =~ ^(([a-zA-Z0-9](-?[a-zA-Z0-9])*)\.)*[a-zA-Z0-9](-?[a-zA-Z0-9])+\.[a-zA-Z]{2,}$ ]]; then
		break
	else
		echo -e "\e[1m\e[31mERR: \e[0mInvalid domain name."
	fi
done

#Network Type
while true; do
	echo -n "Ethernet or Wireless connection [E/w]: "
	read networktype
	if [[ $networktype == "E" ]] || [[ $networktype == "e" ]] || [[ $networktype == "" ]]; then
		#Network type is ethernet
		networktype=ethernet
		break
	elif [[ $networktype == "W" ]] || [[ $networktype == "w" ]]; then
		#Network type is wireless
		networktype=wireless
		break
	else
		echo -e "\e[1m\e[31mERR: \e[0mInvalid selection.  Type E for ethernet or W for wireless."
		networktype=
	fi
done

#Wireless setup
if [[ $networktype == "wireless" ]]; then
	#Get wireless networks
	wlanlist=( $(sudo iwlist wlan0 scan | grep -oP 'ESSID.*"\K.*?(?=")' | sort -u) )
	
	echo -e "\nWireless Network Setup\n"
	
	echo "The following wireless networks are available:"
	i=0
	for ssid in "${wlanlist[@]}"; do
		i+=1
		echo "  $ssid"
	done
	#Get SSID
	while true; do
		echo -ne "\nEnter in the network SSID: "
		read ssid
		if [[ $ssid == "" ]]; then
			#no ssid entered
			echo -e "\e[1m\e[31mERR: \e[0mNo SSID entered."
		else
			break
		fi
	done
	
	#Get PSK
	while true; do
		echo -ne "Enter in the network passkey: "
		read passkey
		if [[ $passkey == "" ]]; then
			#no passkey entered
			echo -e "\e[1m\e[31mERR: \e[0mNo Passkey entered."
		else
			break
		fi
	done	
	
fi

#IP Info
function valid_ip {
    local  ip=$1
    local  stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

function get_static_ip() {
	#Subnet Mask
	while true; do
		echo -n "Enter the subnet mask in CIDR [24]: "
		read subnetmask
		if [[ $subnetmask =~ ^[0-9]+$ ]] && [[ $subnetmask -le 32 ]]; then
			break
		elif [[ $subnetmask -eq "" ]]; then
			subnetmask=24
			break
		else
			echo -e "\e[1m\e[31mERR: \e[0mInvalid subnetmask."
		fi
	done
	
	#Gateway
	while true; do
		echo -n "Enter the gateway: "
		read gateway
		if valid_ip $gateway; then
			break
		else
			echo -e "\e[1m\e[31mERR: \e[0mInvalid gateway."
		fi
	done
	#DNS
	dns=()
	while true; do
		echo "Enter the DNS Server (if you have more than one, enter one at a time, and"
		echo -n "then leave blank to continue): "
		read dns_temp
		if valid_ip $dns_temp; then
			dns+=($dns_temp)
		elif [[ ${#dns[@]} -ne 0 ]] && [[ $dns_temp == "" ]]; then
			#Done adding DNS servers
			break
		else
			echo -e "\e[1m\e[31mERR: \e[0mInvalid DNS server."
		fi
	done
}

while true; do
	echo -n "Enter the IP address, or leave blank for DHCP: "
	read ip
	if [[ $ip == "" ]]; then
		#dhcp
		ip="dhcp"
		break
	elif valid_ip $ip; then
		#static IP, run get other static IP settings
		get_static_ip
		break
	else
		echo -e "\e[1m\e[31mERR: \e[0mInvalid IP Address."
		ip=
	fi
done

# Display network settings for user confirmation
echo -e "\nNetwork Settings:\n"
echo "Hostname: $hostname"
echo "Domain:   $domain"
echo "Network:  $networktype"
if [[ $networktype == "wireless" ]]; then 
	echo "SSID:     $ssid"
	echo "Passkey:  $passkey"
fi
echo "IP:       $ip"
if [[ $ip != "dhcp" ]]; then 
	echo "Subnet:   $subnetmask"
	echo "Gateway:  $gateway"
	for i in "${dns[@]}"; do
		echo "DNS:      $i"
	done
fi

# Get confirmation from user that settings are correct
while true; do
	echo -en "\nAccept these settings and continue? [Y/n]"
	read accept
	if [[ $accept == "Y" ]] || [[ $accept == "y" ]] || [[ $accept == "" ]]; then
		break 2
	elif [[ $accept == "N" ]] || [[ $accept == "n" ]]; then
		break
	else
		echo -e "\e[1m\e[31mERR: \e[0mInvalid Option."
	fi
done
	
done #send us back to the top

#Write settings to log file
echo "Hostname: $hostname" >> $logfile
echo "Domain:   $domain" >> $logfile
echo "Network:  $networktype" >> $logfile
if [[ $networktype == "wireless" ]]; then 
	echo "SSID:     $ssid" >> $logfile
	echo "Passkey:  $passkey" >> $logfile
fi
echo "IP:       $ip" >> $logfile
if [[ $ip != "dhcp" ]]; then 
	echo "Subnet:   $subnetmask" >> $logfile
	echo "Gateway:  $gateway" >> $logfile
	for i in "${dns[@]}"; do
		echo "DNS:      $i" >> $logfile
	done
fi

#Add blank line to screen
echo

###############################################################################
## SECTION 02
##
## Configure network based on user settings
##
## In this section, the network is configured.  First, the hostname is updated,
## and then the wifi adapter is configured (if applicable).  The static ip, if
## set by the user, is the last thing to be configured.
##
## If the user is connecting via SSH, he may be disconnected during this
## section.
#

echo "(2) Configure network..." >> $logfile

echo "+++ (2) CONFIGURE NETWORK +++

WARNING:

If you are currently connected to the RPi via a network connection, your
connection may break.  Please make sure you have an alternate to access the Pi.
"

#Update Hostname
echo "Updating hostname to $hostname..."
echo "Updating hostname to $hostname..." >> $logfile
localaddress="127.0.1.1" #this is a Debian eccentricity
echo "$hostname" | sudo tee /etc/hostname >> $logfile
sudo sed -e "/$localaddress/d" /etc/hosts > /tmp/temp_hosts
sudo echo "$localaddress $hostname.$domain $hostname" >> /tmp/temp_hosts
sudo mv /tmp/temp_hosts /etc/hosts
sudo hostname $hostname
/etc/init.d/hostname.sh start
echo -e "Done.\n"
echo -e "Done.\n" >> $logfile

function add_static_ip {
	int=$1
	
	echo "Adding static IP for int $1..." >> $logfile
	
	echo | sudo tee -a /etc/dhcpcd.conf >> $logfile
	echo "interface $int" | sudo tee -a /etc/dhcpcd.conf >> $logfile
	echo "static ip_address=$ip/$subnetmask" | sudo tee -a /etc/dhcpcd.conf >> $logfile
	echo "static routers=$gateway" | sudo tee -a /etc/dhcpcd.conf >> $logfile
	dnsservers=
	for i in "${dns[@]}"; do
		dnsservers+="$i "
	done
	echo "static domain_name_servers=$dnsservers" | sudo tee -a /etc/dhcpcd.conf >> $logfile
	echo -e "Done.\n"
	echo "Done." >> $logfile
}

#Setup Ethernet Options
if [[ $networktype == "ethernet" ]]; then
	echo "Setting up ethernet network..." >> $logfile
	echo "Setting up ethernet network..."

	#Set Static IP (if required)
	if [[ $ip != "dhcp" ]]; then
		add_static_ip eth0
	fi
	
	sudo ifdown eth0
	sudo ifup eth0
	
	echo -e "Done.\n"
	echo "Done." >> $logfile
fi

#Setup Wifi Options
if [[ $networktype == "wireless" ]]; then
	echo "Setting up wireless network..."
	echo "Setting up wireless network..." >> $logfile
	
	#Use WPA Supplicant to set up network
	new_network=( $( sudo wpa_cli add_network ) )
	networkid=${new_network[${#new_network[@]}-1]} #get the last element of the new_network array
		# this is needed because the add_network command sometimes provides more than one line of output
	sudo wpa_cli set_network $networkid ssid '"'$ssid'"' > $logfile
	sudo wpa_cli set_network $networkid key_mgmt WPA-PSK > $logfile
	sudo wpa_cli set_network $networkid psk '"'$passkey'"' > $logfile
	sudo wpa_cli enable_network $networkid > $logfile
	sudo wpa_cli save_config > $logfile
	
	#Set Static IP (if required)
	if [[ $ip != "dhcp" ]]; then
		add_static_ip wlan0
	fi

	sudo ifdown wlan0
	sudo ifup wlan0
	
	echo -e "Done.\n"
	echo "Done." >> $logfile
fi

#Add blank line to screen
echo

###############################################################################
## SECTION 03
##
## Create PiHerald Users
##
## In this section, the PiHerald users are configured:
##	* piherald (nomal user account)
##	* piherald-admin (admin, sudo account)
##
## The piherald-admin is added to the piherald group, and is given sudo access
## without needing a password.
#

echo "(3) Configure users..." >> $logfile

echo "+++ (3) CONFIGURE USERS +++

The piherald and piherald-admin user accounts are going to be created.
piherald-admin will be added to sudoers and piherald.
"

sudo adduser --disabled-password --gecos "" piherald >> $logfile
sudo adduser --disabled-password --gecos "" piherald-admin >>$logfile

echo "piherald:piherald" | sudo chpasswd >> $logfile
echo "piherald-admin:piherald-admin" | sudo chpasswd >> $logfile

# Add the admin user to the sudoers group and the piherald group
sudo adduser piherald-admin piherald >> $logfile
sudo adduser piherald-admin sudo >> $logfile

# Give users sudo abilities
sudo touch /etc/sudoers.d/piherald
echo "piherald-admin ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/piherald >> $logfile
echo "piherald ALL=(root) NOPASSWD: /usr/bin/tvservice -s" | sudo tee -a /etc/sudoers.d/piherald >> $logfile
echo | sudo tee -a /etc/sudoers.d/piherald >> $logfile
sudo chmod 440 -c /etc/sudoers.d/piherald >> $logfile

echo -e "Done.\n"
echo "Done." >> $logfile

###############################################################################
## SECTION 04
##
## Install XFCE and LightDM
##
## In this section, XFCE and LightDM are installed.  These programs are
## required for PiHerald to work.
#

echo "(3) Installing XFCE and LightDM..." >> $logfile

echo "+++ (3) INSTALLING XFCE and LIGHTDM +++

XFCE and LightDM will now be downloaded from the repos and installed.

This may take a long time.  If it doesn't appear to be doing anything, don't
get impatient.  The last time I ran this on a slow SD card, it took multiple
hours to run.
"

echo "Sleeping until network is up..."
while true; do
	ping -c 1 www.google.com > /dev/null
	if [[ $? -eq 0 ]]; then
		break
	fi
	sleep 5
done

#Update repos and upgrade existing software
echo "Updating Repos and upgrading existing software..." >> $logfile
echo "Updating Repos and upgrading existing software (this may take a long time)..."
sudo apt-get -y -q update >> $logfile
sudo apt-get -y -q upgrade >> $logfile
sudo apt-get -y -q dist-upgrade >> $logfile
echo "Done."

# Install programs for XFCE
echo "Installing programs for XFCE..." >> $logfile
echo "Install programs for XFCE (this may take a long time)..."
sudo apt-get -y -q install --no-install-recommends xserver-xorg >> $logfile
sudo apt-get -y -q install xfce4 xfce4-terminal >> $logfile
sudo apt-get -y -q install lightdm >> $logfile
echo "Done."

# Remove unnecessary programs
echo "Uninstalling screensaver..."
echo "Uninstalling screensaver..." >> $logfile
sudo apt-get -y -q remove xscreensaver >> $logfile
echo -e "Done.\n"
echo "Done." >> $logfile

###############################################################################
## SECTION 05
##
## Get PiHerald Setup files
##
## In this section, the PiHerald setup files are downloaded from the PiHerald
## Server:
##	* piherald-client-update.sh
##
#

echo "(5) Get PiHerald Setup Files..." >> $logfile

echo "+++ (5) GET PiHERALD SETUP FILES +++

The PiHerald files needed to complete setup will now be downloaded from the
PiHerald server.
"

### GET PiHERALD FILES ###
# The only files we should be getting are:
#	* Update script
#
# All other files should be pulled by running the update script.
#

echo "Mounting PiHerald Server..."
echo "Mounting PiHerald Server..." >> $logfile
sudo mount piherald.$domain:/piherald /mnt >> $logfile
echo -e "Done."
echo "Making PiHerald directories and copying files..."

sudo mkdir -p -v /opt/piherald >> $logfile
sudo chown -c -R piherald:piherald /opt/piherald >> $logfile
sudo chmod 775 -c /opt/piherald >> $logfile

sudo install --group=piherald --owner=piherald --mode=770 /mnt/piherald-client-update.sh /opt/piherald/piherald-client-update.sh >> $logfile

sudo umount /mnt >> $logfile

echo -e "Done.\n"

###############################################################################
## SECTION 06
##
## Install PiHerald Packages, get PiHerald Files, and configure PiHerald
##
## In this section, the PiHerald setup files are downloaded and run:
##	* piherald-client-update.sh
##
## The initial config file for initial PiHerald is also downloaded:
##	* piherald-client.ini (initial config)
#

echo "(6) Install PiHerald..." >> $logfile

echo "+++ (6) INSTALL PiHERALD +++

Using the PiHerald update client, PiHerald will now be installed.
"

sudo -u piherald-admin /opt/piherald/piherald-client-update.sh
sudo -u piherald-admin /opt/piherald/piherald-client-update.sh piherald-client

#Make symlink
sudo ln -s /opt/piherald/piherald-client.sh /usr/local/bin/piherald-client

echo "Done."

###############################################################################
## SECTION 07
##
## Configure installed packages.
##
## In this section, the installed packages are configured:
##	* add autologin to LightDM
#

echo "(7) Configure Packages..." >> $logfile

echo "+++ (7) CONFIGURE PACKAGES +++

The installed packages will now be configured.
"

#Configure LightDM autologin
echo "Configure LightDM..."
sudo sed -e "s/.*autologin-user=.*/autologin-user=piherald/" /etc/lightdm/lightdm.conf > /tmp/temp_lightdm
sudo mv /tmp/temp_lightdm /etc/lightdm/lightdm.conf
echo "Done."

###############################################################################
## SECTION 08
##
## Update piherald-client.ini and message PiHerald Server
##
## In this section, the installer updates the locol configuration file, and 
## generates and sends the initial message to the PiHerald Server.
##
## Minor modifications to the RaspberryPi are also made here.
#

echo "(8) Update config and msg server..." >> $logfile

echo "+++ (8) UPDATE and COMMUNICATE +++

Based on information provided in this setup, the local configuration file will
be updated, and a message to the PiHerald server will be generated and sent...
"

#Generate UUID
uuid=`cat /proc/sys/kernel/random/uuid`

#Get IP:
ipaddr=`ip addr | grep -Eo 'inet ([0-9]{1,3}\.){3}[0-9]{1,3}' | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | grep -Ev '127\.([0-9]{1,3}\.){2}[0-9]{1,3}'`

## We're not doing anything with the framebuffer resolutions right now, but I 
## don't want to get rid of this code yet.
#
# Get Res X of framebuffer:
#resx=`sudo fbset -s | grep -Po '^mode "\K[0-9]+x[0-9]+' | grep -Po '[0-9]+(?=x)'` 
#
# Get Res Y of framebuffer:
#resy=`sudo fbset -s | grep -Po '^mode "\K[0-9]+x[0-9]+' | grep -Po 'x\K[0-9]+'` 

#Get Res X of monitor:
resx=`sudo tvservice -s | grep -Po '[0-9]{3,}x[0-9]{3,}' | grep -Po '[0-9]+(?=x)'` 

#Get Res Y of monitor:
resy=`sudo tvservice -s | grep -Po '[0-9]{3,}x[0-9]{3,}' | grep -Po 'x\K[0-9]+'`

#Get TV Group:
tvgroup=`sudo tvservice -s | grep -Po '\[\w+ \K\w+'`

#Get TV Mode:
tvmode=`sudo tvservice -s | grep -Po '\(\K\d+'`

# The framebuffer tells us the resolution of what we see on the screen.  The
# monitor resolution tells us what the display resolution is.  If overscan is
# enabled, then the framebuffer resolution will be less than the resolution of
# the monitor.  Because of usability, if a "TV" is detected, overscan is auto-
# matically enabled, even if it is not needed.  For this reason, we set over-
# scan to be disabled here, but provide the option to enable it through the
# server.
#

#Set Overscan Settings
overscanoverride=1
overscan=0

#Write Overscan settings to config.txt

sudo sed -e "s/^#\?disable_overscan=[01]\?$/disable_overscan=1/" /boot/config.txt > /tmp/temp_bootconfig
sudo install --group=root --owner=root --mode=755 /tmp/temp_bootconfig /boot/config.txt >> $logfile

#Set dhcp
if [[ $ip == "dhcp" ]]; then
	dhcp=1
else
	dhcp=0
fi

#Create DNS list
dnslist=""
for i in "${dns[@]}"; do
	dnslist+="$i "
done

#Set network
if [[ $networktype == "ethernet" ]]; then
	network=eth0
elif [[ $networktype == "wireless" ]]; then
	network=wlan0 
fi

#Updating config file
sudo sed -e "/^\[piheraldclient\]$/,/^\[/ s/^uuid=.*$/uuid=$uuid/; 				`#UUID`\
			 /^\[piheraldclient\]$/,/^\[/ s/^ip=.*$/ip=$ipaddr/; 				`#IP`\
			 /^\[piheraldclient\]$/,/^\[/ s/^subnet=.*$/subnet=$subnetmask/; 	`#Subnet`\
			 /^\[piheraldclient\]$/,/^\[/ s/^gateway=.*$/gateway=$gateway/;		`#Gateway`\
			 /^\[piheraldclient\]$/,/^\[/ s/^dnsservers=.*$/dnsservers=$dnslist/; `#DNS`\
			 /^\[piheraldclient\]$/,/^\[/ s/^dhcp=.*$/dhcp=$dhcp/; 				`#DHCP`\
			 /^\[piheraldclient\]$/,/^\[/ s/^hostname=.*$/hostname=$hostname/; 	`#Hostname`\
			 /^\[piheraldclient\]$/,/^\[/ s/^domain=.*$/domain=$domain/;		`#Domain`\
			 /^\[piheraldclient\]$/,/^\[/ s/^network=.*$/network=$network/; 	`#Network`\
			 /^\[piheraldclient\]$/,/^\[/ s/^ssid=.*$/ssid=$ssid/;			 	`#SSID`\
			 /^\[piheraldclient\]$/,/^\[/ s/^psk=.*$/psk=$passkey/;				`#Passkey`\
			 /^\[piheraldclient\]$/,/^\[/ s/^resx=.*$/resx=$resx/; 				`#ResX`\
			 /^\[piheraldclient\]$/,/^\[/ s/^resy=.*$/resy=$resy/; 				`#ResY`\
			 /^\[piheraldclient\]$/,/^\[/ s/^tvgroup=.*$/tvgroup=$tvgroup/; 	`#TV Group`\
			 /^\[piheraldclient\]$/,/^\[/ s/^tvmode=.*$/tvmode=$tvmode/;		`#TV Mode`\
			 /^\[piheraldclient\]$/,/^\[/ s/^overscanoverride=.*$/overscanoverride=$overscanoverride/; `#Overscan Override`\
			 /^\[piheraldclient\]$/,/^\[/ s/^overscan=.*$/overscan=$overscan/;	`#Overscan`\
			 " /opt/piherald/piherald-client.ini > /tmp/temp_piherald-client
sudo install --group=piherald --owner=piherald --mode=660 /tmp/temp_piherald-client /opt/piherald/piherald-client.ini >> $logfile		 

#Send the message to the server:

sudo -u piherald-admin perl /opt/piherald/piherald-client-comm.pl

echo "+++ INSTALL COMPLETE +++

Please review the install, and make sure there were no errors.  Some simple
checks to run:
  - su piherald-admin - can you switch to the created user?
  - ls /opt/piherald  - are the PiHerald files installed?
  - piherald-client   - does the piherald-client command work?
"
