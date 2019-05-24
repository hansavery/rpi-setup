#!/usr/bin/env bash


# scriptdir variable is set when script is first created from template
scriptdir=""


# other variables are set when the script is configured
# add variables here >>>


# only run on first boot
[ -f $scriptdir/first ] && exit 0

function main {
# add calls here >>>

  touch $scriptdir/first # create file to indicate this script has already been run
  echo '### Finished! Restarting...' && reboot
}


# add functions here >>>
# ... and let's hope that all worked.
main > "$scriptdir/first_boot_log.txt" 2>&1
