#!/bin/bash

# This script prompts the user to change the keyboard, locale, and timezone of
# the Raspberry Pi.
#
# By default, this assumes that your Raspberry Pi is located in the US (which 
# means en_US-UTF-8 language and en_US keyboard), and located in the Pacific
# Timezone (America/Los_Angeles)
#
# This script allows you to update to a different timezon by supply the TZ
# timezone as the first argument.

clear

logfile=/tmp/piherald-client-locales.log
touch $logfile


### LOCALE SETTINGS ###

# Change keyboard to US layout
# In theory, this shouldn't matter, but while developing, it makes it difficult for me if the keyboard layout is not US

echo -e "\nUpdating keyboard and locale to US English..."

sudo sed -e "s/XKBLAYOUT.*/XKBLAYOUT=\"us\"/" /etc/default/keyboard > /tmp/temp_keyboard
sudo mv /tmp/temp_keyboard /etc/default/keyboard
sudo setupcon -k

# Update Timezone

if [[ $1 == "" ]]; then
	timezone=America/Los_Angeles
else
	timezone=$1
fi

echo "$timezone" | sudo tee /etc/timezone >> $logfile
sudo dpkg-reconfigure -f noninteractive tzdata

# Update locale to US
echo "You will now be prompted to set your locale."
echo "Please unselect en_GB, and select en_US."
echo
echo "Press enter to continue..."
read

sudo dpkg-reconfigure locales

echo "Done."

echo
echo "Please reboot after changing locale."