#!/bin/bash

# flash_device expects two inputs: the image path and the device name
# Confirms that the image exists and that the target device exists.
# Confirms that the device is a usb device.
# Writes to the device
function flash_device {
  local img=${1:?first argument should be disk image}
  local target=${2:?second argument should be device target}

  # Check that disk image exists
  [ ! -f $img ] && echo "Image file $img not found." 1>&2 && return 1

  # Check that target device exists
  bulk_device_exists $target || return 1

  # Confirm that target is valid USB device
  local usb=$(find_usb_device $target) || return 1

  # Write to target device
  if ! write_to_device $usb $img; then
    echo "Error flashing device $usb." 1>&2
    return 1
  fi
}

# set_boot_and_root finds the boot and root partitions on a newly flashed
# device, then exports them as non-local variables.
function set_boot_and_root {
  local usb=$1
  # Find partitions
  if ! partitions=($(find_boot_root $usb)); then
    echo "Error finding partitions on $usb." 1>&2
    return 1
  fi
  # these next to SHOULD BE globals...
  boot=${partitions[0]}
  root=${partitions[1]}
}


# If an argument has been provided then check that it is a valid device.
# The lsblk program will return a list of bulk storage devices.
function bulk_device_exists {
  local targetdevice=$1
  local devices=($(lsblk | grep -o '^sd.'))
  if [ "$targetdevice" != "" ]; then
    for d in "${devices[@]}"; do
      if [ "$d" = "$targetdevice" ]; then
        return 0
      fi
    done
  fi
  echo "Could not find target device $targetdevice." 1>&2
  return 1
}


# Find usb device. If device was provided, this step confirms that it
# is usb. udevadm returns info about devices, including whether they
# are usb. Loop through all bulk storage devices and exit when the
# first usb device is found. If no device is found exit with an error.
# If targetdevice was unspecified then ask for confirmation.
function find_usb_device {
  if [ -z $1 ]; then
    local devices=($(lsblk | grep -o '^sd.'))
  else
    local devices=$1
  fi
  for dev in "${devices[@]}"; do
    if $(udevadm info --name $dev | grep --quiet "ID_BUS=usb"); then
      local discovered=$dev
      break
    fi
  done
  if [ -z $discovered ]; then
    echo 1>&2 "Couldn't find usb device"
    return 1
  fi
  echo $discovered
  return 0
}


# Flashes device (for example, "sdb") with zipped image file.
# Takes device name as $1 and image file as $2.
function write_to_device {
  local usb=$1
  local img=$2

  # Get partitions, unmount all
  local pre_partitions=$(mount | grep -o "^/dev/$usb\S*")
  for p in ${pre_partitions[@]}; do udisksctl unmount -b "$p" > /dev/null; done

  # Flash the device
  if [ ${img: -4} == ".zip" ]; then
    unzip -p $img | sudo dd bs=4M of=/dev/$usb conv=fsync
  else
    sudo dd bs=4M if=$img of=/dev/$usb conv=fsync
  fi
  sync

  # Recheck partitions, remount
  # sleep is needed after partprobe; otherwise call to lsblk below might not return partitions
  sudo partprobe /dev/$usb
  sleep 1 
  local post_partitions=$(lsblk | grep -oP "$usb\d")
  for p in ${post_partitions[@]}; do udisksctl mount -b "/dev/$p" >> /dev/null; done
}


# There should be one boot mountpoint and one for the main filesystem.
# The name of the filesysteem mountpoint may change, so test for two and
# for one of them being named "boot". Exit if conditions are not met.
function find_boot_root {
  local usb=$1
  local mountpoints=($(mount | grep -oP "(?<=$usb\d\son\s)\S+"))
  local count=${#mountpoints[@]}
  if [ $count -ne 2 ]; then
    echo "Wrong number of mount points. Expected 2 got $count." 1>&2
    return 1
  fi
  for m in "${mountpoints[@]}"; do
    if $(echo "$m" | grep --quiet "boot$"); then
      boot=$m
    else
      root=$m
    fi
  done
  if [ "$boot" = "" ] || [ "$root" = "" ]; then
    echo "Couldn't identify boot and root partitions." 1>&2
    return 1
  fi
  echo "$boot $root"
}

# Unmount and power off drive so that it can be removed
function power_down_usb {
  local usb=$1
  part=$(mount | grep -o "^/dev/$usb\S*")
  for p in ${part[@]}; do
    udisksctl unmount -b $p > /dev/null
    if [ $? -ne 0 ]; then
      echo "Error unmounting partition $p." 1>&2
      return 1
    fi
  done
  udisksctl power-off -b /dev/$usb
  if [ $? -ne 0 ]; then
    echo "Error powering down device $usb." 1>&2
    return 1
  fi
}
