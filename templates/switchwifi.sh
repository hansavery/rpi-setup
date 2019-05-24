#!/usr/bin/env bash


# Get current status
wifi_status=$(iwgetid | grep -E 'ESSID:".+"' > /dev/null; echo $?)
ap_status=$(iw wlan0 info | grep "type AP" > /dev/null; echo $?)
if [ "$wifi_status" -eq 0 ]; then
  echo "### Found external wifi connection"
  current="wifi"
  default="ap"
elif [ "$ap_status" -eq 0 ]; then
  echo "### Found active access point"
  current="ap"
  default="wifi"
else
  current="none";
  default="ap"
fi


# Check input and exit early if bad target or no change necessary
target=$1
if [ "$target" = "" ]; then
  target=$default
elif [ "$target" = "any" ] && [ "$current" != "none" ]; then
  exit 0
elif [ "$target" = "$current" ]; then
  exit 0
elif [ "$target" != "" ] && [ "$target" != "ap" ] && [ "$target" != "wifi" ]; then
  echo "### Invalid target for wifi switch ('$target')"
  exit 1
fi


# Make the switch
echo "### Switching wireless to $target mode"
systemctl stop dnsmasq
systemctl stop hostapd
systemctl stop wpa_supplicant
if [ "$target" = "ap" ]; then
  systemctl stop dhcpcd
  cp /etc/dhcpcd.conf_ap /etc/dhcpcd.conf
  systemctl daemon-reload
  systemctl start dhcpcd
  systemctl start dnsmasq
  systemctl start hostapd
elif [ "$target" = "wifi" ]; then
  systemctl stop dhcpcd
  cp /etc/dhcpcd.conf_client /etc/dhcpcd.conf
  systemctl daemon-reload
  systemctl start dhcpcd
  systemctl start wpa_supplicant
fi


# Exit on success, otherwise try falling back to other connection
wifi_status=$(iwgetid | grep -E 'ESSID:".+"' > /dev/null; echo $?)
ap_status=$(iw wlan0 info | grep "type AP" > /dev/null; echo $?)
if [ "$target" = "wifi" ] && [ "$wifi_status" -eq 0 ]; then
  exit 0
elif [ "$target" = "ap" ] && [ "$ap_status" -eq 0 ]; then
  exit 0
elif [ "$target" = "wifi" ] && [ "$wifi_status" -ne 0 ]; then
  target="ap"
elif [ "$target" = "ap" ] && [ "$ap_status" -ne 0 ]; then
  target="wifi"
else
  exit 1
fi

echo "### Error! Switching wireless to $target mode"
systemctl stop dnsmasq
systemctl stop hostapd
systemctl stop wpa_supplicant
if [ "$target" = "ap" ]; then
  systemctl stop dhcpcd
  cp /etc/dhcpcd.conf_ap /etc/dhcpcd.conf
  systemctl daemon-reload
  systemctl start dhcpcd
  systemctl start dnsmasq
  systemctl start hostapd
elif [ "$target" = "wifi" ]; then
  systemctl stop dhcpcd
  cp /etc/dhcpcd.conf_client /etc/dhcpcd.conf
  systemctl daemon-reload
  systemctl start dhcpcd
  systemctl start wpa_supplicant
fi


# Check connection status and exit with error code if not connected
wifi_status=$(iwgetid > /dev/null 2> /dev/null; echo $?)
ap_status=$(iw wlan0 info | grep "type AP" > /dev/null; echo $?)
if [ "$target" = "wifi" ] && [ "$wifi_status" -eq 0 ]; then
  exit 0
elif [ "$target" = "ap" ] && [ "$ap_status" -eq 0 ]; then
  exit 0
else
  echo "### Error! Couldn't make connection"
  exit 1
fi