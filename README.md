# rpi-setup
Setup scripts for the Raspberry Pi, because memorizing settings is hard. Tested on Ubuntu 14.04 and 18.04 with the November 13 2018 release of Raspbian Stretch Lite.

The example script, basic\_headless\_setup.sh, will take a device name (for example, 'sda', 'sdb', or 'sdc') and the path to a disk image as arguments. For example:

`basic_headless_setup.sh sdb ./diskimages/2018-11-13-raspbian-stretch-lite.zip`

By default, the basic headless setup sets the keyboard layout, configures wifi, updates the host name, and copies ssh keys. It also creates a script to run on the Pi's first boot which enables ssh, sets the timezone, downloads system updates, and installs the programs needed to create a wifi access point. Wifi configuration, location info, and other secrets are taken from the secrets.sh file. Setup steps have been coded in functions so that they can be easily added to/removed from the script.

### run with sudo
Flashing the drive takes root permissions.

### find device using lsblk
The setup script is looking for the device id as an argument. This is typically three characters, for example "sdb". You can find the device id with lsblk but lsblk lists partitions and loop devices too, so use grep with it to isolate the "disk" lines. Run `lsblk | grep ".*disk.*"` to get the lsblk results and pass them to grep, which will then display only the lines that have "disk" somewhere in them. Run it once to see what bulk storage devices you have, then plug in the device, run it again, and find the new entry in the list. For example, you might see:

```
sda        8:0      0    238.5G  0   disk
```

... on your first run, and:

```
sda        8:0      0    238.5G  0   disk
sdb        9:0      0    477.0G  0   disk
```

... on the second, in which case sdb is the device to flash.

### put names, locations, credentials, etc. in a secrets.sh file.
The repository is set up to ignore secrets.sh. Put hostname, location info, wifi credentials, etc. in that file so that they are not checked in to the repository. There is an example file in the templates directory (remember to rename it so that it does not get checked in).
