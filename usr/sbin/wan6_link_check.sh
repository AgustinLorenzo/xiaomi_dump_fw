#!/bin/sh

mode=$(uci -q get ipv6.settings.mode)
if [ "$mode" == "nat" ]; then
    status_wan_6=$(/sbin/ifstatus wan_6 | grep up | awk 'NR==1 {print $2}' | sed -e 's/,//')
    [ -z "$status_wan_6" -o "$status_wan_6" = "false" ] && exit 0
fi
exit 1
