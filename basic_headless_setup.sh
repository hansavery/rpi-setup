#!/bin/bash

source ./lib/flash.sh
source ./lib/rpi.sh

function main {
  local usb=${1:?"script requires usb device name as first arg"}
  local img=${2:?"script requires disk image path as second arg"}
  source ./secrets.sh

  flash_device $img $usb || return 1
  set_boot_and_root $usb || return 1

  # >>>> config specifics start here
  turn_off_rpi_logo $boot || return 1
  
  configure_keyboard $root || return 1
  update_wpa_supplicant $root $homewifiname $homewifipass || return 1
  update_hostname $root $hostname || return 1
  local home=$(eval echo ~${SUDO_USER})
  ssh-keygen -f "$home/.ssh/known_hosts" -R "$hostname.local"
  copy_ssh_hostkey $root || return 1

  local first_path='templates/first_boot.sh'
  local tmppath=$(mktemp /tmp/first_boot.XXXXXXXX.sh)
  create_first_boot_script $tmppath || return 1
  add_function_to_first_boot $tmppath enable_ssh
  add_function_to_first_boot $tmppath set_timezone $timezone
  add_function_to_first_boot $tmppath update_system
  add_function_to_first_boot $tmppath set_up_access_point $apname $appass $apchannel
  add_script_to_boot_routine $root $tmppath || return 1
  rm $tmppath

  # on boot, start access point if can't connect to known network
  wifi_path="templates/switchwifi.sh" || return 1
  add_script_to_boot_routine $root $wifi_path "wifi" || return 1
  # <<<< config specifics end here

  power_down_usb $usb || return 1
  echo "Success! Wrote image $img to device $usb."
}

main $@
