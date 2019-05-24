#!/usr/bin/bash

rpi_functions=0
rpi_setupscript_dir="/usr/local/setupscripts"

function turn_off_rpi_logo {
  local mountpoint=${1:?"turn_off_rpi_logo requires mountpoint for boot partition"}
  
  echo 'Turning off rpi logo...'
  cp "$mountpoint/cmdline.txt" "$mountpoint/cmdline.txt_prelogo"
  sed -i 's|$| logo.nologo|' "$mountpoint/cmdline.txt"
}


function configure_keyboard {
  local mountpoint=${1:?"configure_keyboard requires mountpoint for root partition"}
  local model=${2:-"pc105"}
  local layout=${3:-"us"}

  echo 'Updating keyboard settings...'
  cp "$mountpoint/etc/default/keyboard" "$mountpoint/etc/default/keyboard_preconfig"
  sed -i 's/XKBMODEL=.*$/XKBMODEL="'$model'"/' "$mountpoint/etc/default/keyboard"
  sed -i 's/XKBLAYOUT=.*$/XBKLAYOUT="'$layout'"/' "$mountpoint/etc/default/keyboard"
}


function update_wpa_supplicant {
  local mountpoint=${1:?"update_wpa_supplicant requires mountpoint for root partition"}
  local wifiname=${2:?"update_wpa_supplicant requires wifi name argument"}
  local wifipass=${3:?"update_wpa_supplicant requires wifi password argument"}

  echo 'Updating wpa_supplicant.conf...'
  cp "$mountpoint/etc/wpa_supplicant/wpa_supplicant.conf" "$mountpoint/etc/wpa_supplicant/wpa_supplicant.conf_preupdate"
  echo "network={
    ssid=\"$wifiname\"
    psk=\"$wifipass\"
  }" >> "$mountpoint/etc/wpa_supplicant/wpa_supplicant.conf"
}


function update_hostname {
  local mountpoint=${1:?"update_hostname requires mountpoint for root partition"}
  local hostname=${2:?"update_hostname requires hostname argument"}

  echo 'Updating hostname...'
  cp "$mountpoint/etc/hostname" "$mountpoint/etc/hostname_preupdate"
  echo "$hostname" > "$mountpoint/etc/hostname"
}


function copy_ssh_hostkey {
  local mountpoint=${1:?"copy_ssh_hostkey requires mountpoint argument"}
  echo 'Copying ssh hostkey...'
  if [ -f ~/.ssh/id_rsa.pub ]; then
    mkdir -p /$mountpoint/home/pi/.ssh
    cat ~/.ssh/id_rsa.pub >> $mountpoint/home/pi/.ssh/authorized_keys
  fi
}


function create_first_boot_script {
  local script_path=${1:?"create_first_boot_script requires path to save customized script"}

  local template_dir="$PWD/templates"
  local template="$template_dir/first_boot.sh"
  cp $template $script_path
  sed -i "s|scriptdir=.*$|scriptdir='$rpi_setupscript_dir'|" "$script_path"
}


function add_variable_to_first_boot {
  local script_path=${1:?"add_variable_to_first_boot requires path to save customized script"}
  local variable=${2:?"add_variable_to_first_boot requires variable name as second argument"}
  local value=${3:?"add_variable_to_first_boot requires variable value as second argument"}  

  local instancestr="local $variable=\"$value\""
  sed -i "/\# add variables here >>>/a$instancestr" "$script_path"
}


function add_function_to_first_boot {
  local script_path="${1:?"add_function_to_first_boot requires path to save customized script"}"
  local func_name="${2:?"add_function_to_first_boot requires function name as second argument"}"

  # create a func_args variable with all remaining arguments as quoted strings
  # for example if args are (a, b, "c d", e) then func_args should be ("a" "b" "c d" "e")
  local first_arg="$3" # get first argument
  if shift 3; then # if that first argument existed...
    # next line uses bash parameter expansion to transform ${@/#/_} into _arg1_arg2_arg3...
    local func_args=$(printf "%s" "\"$first_arg${@/#/\" \"}\"") # use printf with "%s" to avoid trailing spaces
  else
    local func_args=""
  fi

  # get function text and serialize
  local func_text="$(type $func_name | sed '1d')"
  [ -z "$func_text" ] && echo "Couldn't find function $func_name" 1>&2 && return 1
  local serialized=$(echo "$func_text" | sed 's|$|\\|' | tr '\n' 'n')

  # insert function name in main, then insert defintion before main is called
  sed -i "/\# add calls here >>>/a$func_name $func_args
          /\# add functions here >>>/a$serialized\n\n" "$script_path"
}


function add_script_to_boot_routine {
  local mountpoint=${1:?"add_script_to_boot_routine requires mountpoint argument"}
  local file_to_copy=${2:?"add_script_to_boot_routine requires path of script to add as argument"}
  if [ ! -f "$file_to_copy" ]; then
    echo "could not find $file_to_copy"
    return 1
  fi
  shift 2

  local file_name=$(basename $file_to_copy)
  tmpdir=$rpi_setupscript_dir
  mkdir -p $mountpoint/$tmpdir
  cp $file_to_copy "$mountpoint/$tmpdir/$file_name"
  chmod u+x "$mountpoint/$tmpdir/$file_name"
  sed -i "\$i $tmpdir/$file_name $@" "$mountpoint/etc/rc.local"
}


function update_system {
  apt-get update -y
  apt-get upgrade -y
}


function enable_ssh {
  systemctl enable ssh
  systemctl start ssh
}


function set_up_access_point {
  local apname=${1:?"set_up_access_point requires apname argument"}
  local appass=${2:?"set_up_access_point requires appass argument"}
  local apchannel=${3:?"set_up_access_point requires apchannel argument"}

  echo '### Installing hostapd and dnsmasq; disabling for boot script control'
  apt-get install hostapd dnsmasq -y
  systemctl disable dnsmasq
  systemctl disable hostapd

  echo '### Establishing dhcpcd configuration'
  # note that unlike hostapd and dnsmasq, this needs separate client and ap versions
  cp /etc/dhcpcd.conf /etc/dhcpcd.conf_original
  cp /etc/dhcpcd.conf /etc/dhcpcd.conf_client
  echo '
interface wlan0
  static ip_address=192.168.50.1/24
  nohook wpa_supplicant
' > /etc/dhcpcd.conf_ap

  echo '### Establishing dnsmasq configuration'
  cp /etc/dnsmasq.conf /etc/dnsmasq.conf_original
  echo '
interface=wlan0
dhcp-range=192.168.50.2,192.168.50.20,255.255.255.0,24h
' > /etc/dnsmasq.conf

  echo '### Establishing hostapd configuration'
  # hostapd does not come with a .conf file so there is nothing to back up...
  echo "
interface=wlan0
driver=nl80211
ssid=$apname
wpa_passphrase=$appass
hw_mode=g
channel=$apchannel
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
" > /etc/hostapd/hostapd.conf  
  cp /etc/default/hostapd /etc/default/hostapd_original
  sed -i 's|#DAEMON_CONF.*$|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' "/etc/default/hostapd"
  sed -i 's|DAEMON_OPTS.*$|DAEMON_OPTS="-dd"|' "/etc/default/hostapd"
  # next line comes with many thanks to fabrizio.dini for the post @ https://www.raspberrypi.org/forums/viewtopic.php?t=73991
  # the "fixed version" doesn't appear to be actually fixed (doesn't look different from what is there),
  # but the point made -- that /etc/init.d/hostapd is redefining DAEMON_CONF was the key to getting this working
  sed -i 's|DAEMON_CONF=$|#DAEMON_CONF=|' '/etc/init.d/hostapd'
}


function enable_i2c {
  local mountpoint=${1:?"enable_i2c requires mountpoint for root partition"}

  echo 'Enabling i2c...'
  cp "$mountpoint/boot/config.txt" "$mountpoint/boot/config.txt_prei2c"
  echo "" >> "$mountpoint/boot/config.txt"
  echo "# Enable i2c support" >> "$mountpoint/boot/config.txt"
  echo "dtparam=i2c_arm=on" >> "$mountpoint/boot/config.txt"
}


function enable_1wire {
  local mountpoint=${1:?"enable_1wire requires mountpoint for root partition"}

  echo 'Enabling 1wire...'
  cp "$mountpoint/boot/config.txt" "$mountpoint/boot/config.txt_pre1wire"
  echo "" >> "$mountpoint/boot/config.txt"
  echo "# Enable 1-Wire protocol support" >> "$mountpoint/boot/config.txt"
  echo "dtoverlay=w1-gpio" >> "$mountpoint/boot/config.txt"
}


function set_timezone {
  local timezone=${1:-"America/Los_Angeles"}
  echo "Setting timzone to $timezone..."
  timedatectl set-timezone $timezone
}
