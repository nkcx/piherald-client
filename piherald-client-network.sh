#!/bin/bash

# This script walks you through the setup for a RaspberryPi to be used for
# PiHerald.  Hopefully, I'll be able to create a custom image that has all
# of this someday, but that day is not today.
#
# This script does the following:
#	(1) Prompts the user for network settings.
#	(2) Sets up network.
#	(3) Updates RaspberryPi.
#	(4) Installs necessary packages.
#	(5) Configures packages.
#	(6) Creates and configures users.
#	(7) Installs PiHerald files.
#
# The script makes a critical assumption about the setup:
#   -The image is based on Rasbian Jessie Lite
#
# The script also makes a few less than critical assumptions that only need to
# be met during setup, and can be changed later.
#	-The ethernet adapter is eth0
#	-The wireless adapter is wlan0
#	-All wireless networks the user wants to connect to are WPA[2]-PSK
#	-The keyboard and locales are all US English

clear

logfile=/tmp/piherald-client-setup.log
touch $logfile

### WELCOME ####
echo "PiHerald Install v0.1

Welcome to the PiHerald Installer!  This installer assumes that you are
running on a Jessie Rasbian Lite image from the RaspberryPi Foundation.

First, the installer is going to ask you a few questions about your network
setup:
"

#If the first argument is "skip", then skip over the network stuff
if [[ $1 != "skip" ]]; then

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

function static_ip() {
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
		static_ip
		break
	else
		echo -e "\e[1m\e[31mERR: \e[0mInvalid IP Address."
		ip=
	fi
done

#echo -n "Enter the NTP server []: "
#read ntp

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
echo -e "\nNetwork Settings:\n" >> $logfile
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

echo

### NETWORK SETTINGS ###

echo -e "SETTING UP NETWORK\n"
echo -e "WARNING:\n"
echo -e "If you are currently connected to the RPi via a network connection, your"
echo -e "connection may break.  Please make sure you have an alternate to access the Pi."
echo -ne "\nHit enter to continue..."
read
echo

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
}

#Setup Ethernet Options
if [[ $networktype == "ethernet" ]]; then
	echo "Setting up ethernet network..."

	#Set Static IP (if required)
	if [[ $ip != "dhcp" ]]; then
		add_static_ip eth0
	fi
	
	sudo ifdown eth0
	sudo ifup eth0
	
	echo -e "Done.\n"
fi

#Setup Wifi Options
if [[ $networktype == "wireless" ]]; then
	echo "Setting up wireless network..."
	
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
fi

fi #close out the "skip" if

### UPDATE RASPBERRY PI ###
# (And do a few other things too)

echo "Sleeping until network is up..."
while true; do
	ping -c 1 www.google.com > /dev/null
	if [[ $? -eq 0 ]]; then
		break
	fi
	sleep 5
done

#Update repos and upgrade existing software
echo -e "\nUpdating Repos and upgrading existing software (this may take a while)..."
sudo apt-get -y -q update >> $logfile
sudo apt-get -y -q upgrade >> $logfile
sudo apt-get -y -q dist-upgrade >> $logfile
echo "Done."

### INSTALL PROGRAMS ###

# Install programs for XFCE
echo "Install programs for XFCE (this may take a while)..."
sudo apt-get -y -q install --no-install-recommends xserver-xorg >> $logfile
sudo apt-get -y -q install xfce4 xfce4-terminal >> $logfile
sudo apt-get -y -q install lightdm >> $logfile
sudo apt-get -y -q install xtightvncviewer >> $logfile
echo "Done."

# Remove unnecessary programs
echo "Uninstalling screensaver..."
sudo apt-get -y -q remove xscreensaver >> $logfile
echo "Done."

# Clean up install
echo "Cleaning up install"
sudo apt-get -y -q autoremove >> $logfile
sudo apt-get -y -q clean >> $logfile
echo "Done."

#Configure LightDM autologin
echo "Configure LightDM..."
sudo sed -e "s/.*autologin-user=.*/autologin-user=piherald/" /etc/lightdm/lightdm.conf > /tmp/temp_lightdm
sudo mv /tmp/temp_lightdm /etc/lightdm/lightdm.conf
echo "Done."

### ADD USERS ###

# We are going to create two users:
#  (1) piherald - the day-to-day user
#  (2) piherald-admin - the user account with admin (sudo) privileges
#

sudo adduser --disabled-password --gecos "" piherald
sudo adduser --disabled-password --gecos "" piherald-admin

echo "piherald:piherald" | sudo chpasswd
echo "piherald-admin:piherald-admin" | sudo chpasswd

sudo adduser piherald-admin piherald
sudo adduser piherald-admin sudo

### GET PiHERALD FILES ###
sudo mount piherald.$domain:/piherald /mnt

sudo mkdir -p /opt/piherald
sudo cp -r /mnt/* /opt/piherald/

sudo umount /mnt

sudo chown piherald:piherald /opt/piherald/*

### INSTALL FILES ###

# CP XFCE config to PiHerald user account
sudo mkdir -p /home/piherald/.config/xfce4/xfconf/xfce-pechannel-xml/ 
sudo cp /opt/piherald/xfce4-panel.xml /home/piherald/.config/xfce4/xfconf/xfce-pechannel-xml/ 
sudo cp /opt/piherald/xfwm4.xml /home/piherald/.config/xfce4/xfconf/xfce-pechannel-xml/ 

# CP startup file to PiHerald user account
sudo mkdir -p /home/piherald/.config/autostart/
sudo cp /opt/piherald/vncviewer.desktop /home/piherald/.config/autostart/

sudo chown -R piherald:piherald /home/piherald/.config

### LOCALE SETTINGS ###

# Change keyboard to US layout
# In theory, this shouldn't matter, but while developing, it makes it difficult for me if the keyboard layout is not US

echo -e "\nUpdating keyboard and locale to US English..."

sudo sed -e "s/XKBLAYOUT.*/XKBLAYOUT=\"us\"/" /etc/default/keyboard > /tmp/temp_keyboard
sudo mv /tmp/temp_keyboard /etc/default/keyboard
sudo setupcon -k

# Update locale to US
echo "You will now be prompted to set your locale."
echo "Please unselect en_GB, and select en_US."
echo
echo "Press enter to continue..."
read

sudo dpkg-reconfigure locales

echo "Done."
