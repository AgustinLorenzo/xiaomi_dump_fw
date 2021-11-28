#!/bin/sh
# Copyright (C) 2015 Xiaomi
. /lib/functions.sh

enable=$(uci -q get ipv6.settings.enabled)
mode=$(uci -q get ipv6.settings.mode)

if [ "$enable" = "1" ]; then
    /etc/init.d/ipv6 start_ipv6 $mode $mode "restore_cfg"
fi
uci -q batch <<EOF
    delete network.lan.ipv6
	commit network
EOF
