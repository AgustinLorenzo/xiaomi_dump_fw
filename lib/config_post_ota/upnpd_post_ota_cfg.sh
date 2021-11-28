#!/bin/sh
# Copyright (C) 2015 Xiaomi

rule=$(uci show upnpd | grep "Allow high ports" | cut -d '.' -f 2) 
[ -z "$rule" ] && return 0

int_ports=$(uci -q get upnpd.$rule.int_ports)
[ "$int_ports" != "1-65535" ] && {
	uci -q batch <<EOF
		set upnpd.$rule.int_ports='1-65535'
		commit upnpd
EOF
}
