#!/bin/bash

## PiHERALD CLIENT SOFTWARE SUITE
## VERSION: 0.1
## (C): Nicholas Card, 2016
##
## piherald-client-tvservice.sh
#
# This script is used to get tvservice information.
#
# Unfortunately, on the Raspberry Pi, the tvservice binary is only usable by
# root.  We use this script (with suid) to give all users permission to get the
# tvservice information without needed to give all users the ability to manipu-
# late the monitor settings.
#
tvservice -s
