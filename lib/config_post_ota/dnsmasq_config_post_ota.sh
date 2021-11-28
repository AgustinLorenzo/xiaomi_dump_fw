#!/bin/sh

/sbin/uci -q batch <<EOF >/dev/null
set dhcp.@dnsmasq[0].allservers='1'
commit dhcp
EOF
