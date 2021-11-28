#!/bin/sh

. /lib/functions.sh
config_load misc

advcap2bitmap() {
	# Not currently in use, to be done
	:
}

# Power on all LAN ports
sw_start_lan() {
	for lan in `uci get network.lan.ifname`
	do
		[ -f /sbin/ifconfig ] && ifconfig $lan up
	done
}

# Power off all LAN ports
sw_stop_lan() {
	for lan in `uci get network.lan.ifname`
	do
		[ -f /sbin/ifconfig ] && ifconfig $lan down
	done
}

# Detect link on WAN port
sw_wan_link_detect() {
	local wan_name=$(uci get network.wan.ifname) 
	cat /sys/class/net/$wan_name/carrier | grep -q 1 
}

# Count link on all LAN port
sw_lan_count() {
	local count=0
	for lan_port in `uci get network.lan.ifname`
	do
		local lan1=`swconfig dev switch0 port $lan_port get link | grep "up"`;
		if [ -n "$lan1" ]; then
			$count=`expr $count + 1`
		fi
	done
	
	echo $count
}

# 100Mb advertisement on WAN port enabled?
sw_is_wan_100m() {
	local wan_port=$(uci get misc.sw_reg.sw_wan_port)

	swconfig dev switch0 port $wan_port get link | grep "speed:100b"
}

# 1000Mb advertisement on WAN port enabled?
sw_is_wan_giga() {
	local wan_port=$(uci get misc.sw_reg.sw_wan_port)

	swconfig dev switch0 port $wan_port get link | grep "speed:1000b"
}

# Limit PHY speed advertisement on WAN port to special speed
sw_set_wan_neg_speed() {
	local wan_port=$(uci get misc.sw_reg.sw_wan_port)
	local reg=0x23f
	
    case "$1" in
	0)
		reg=0x23f
		;;
	10)
		reg=0x033
		;;
	100)
		reg=0x03c
		;;
	1000)
	    reg=0x230
	    ;;
	*)
	    echo "unsupport speed!"
	    return 1
	    ;;
    esac
	
	ssdk_sh port autoAdv set $wan_port $reg
	ssdk_sh port autoNeg restart $wan_port
	
	return 0
}

# Trigger WAN port PHY renegotiation
sw_reneg_wan() {
	# Not currently in use, to be done
	:
}

# Enable EAPOL frame forwarding between CPU port and WAN port
sw_allow_eapol() {
	# Not currently in use, to be done
	:
}

# Disable EAPOL frame forwarding between CPU port and WAN port
sw_restore_eapol() {
	# Not currently in use, to be done
	:
}
