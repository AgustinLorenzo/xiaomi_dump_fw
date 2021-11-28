#!/bin/sh

# mimesh_stat: check stat

. /lib/mimesh/mimesh_public.sh

ERR_ROLE=10

__ts_get()
{
	local ts="`date +%Y%m%d-%H%M%S`:`cat /proc/uptime | awk '{print $1}'`"
	echo -n "timestamp:$ts"
}

# check device is CAP or RE
mimesh_is_cap()
{
	local mode=$(uci -q get xiaoqiang.common.NETMODE)
	[ "whc_cap" = "$mode" ] && return 0 || {
		[ "lanapmode" = "$mode" ] && {
			[ "`uci -q get xiaoqiang.common.CAP_MODE`" = "ap" ] && return 0
		}
	}

	return $ERR_ROLE
}

mimesh_is_re()
{
	[ "`uci -q get xiaoqiang.common.NETMODE`" = "whc_re" ] && return 0 || return $ERR_ROLE

	return 0
}

# return CAP RE 
mimesh_get_stat()
{
	mimesh_is_cap && {
		echo -n "CAP"
		return 0
	}

	mimesh_is_re && {
		echo -n "RE"
		return 0
	}

	echo -n "router"
	return 0;
}

mimesh_get_gw_ip()
{
	local __NLAL_netw="$1"
	local __NLAL_gw_ip="`route -n  | grep "^0.0.0.0" | grep br-$__NLAL_netw | awk '{print $2}' | xargs`"
	[ -z "$__NLAL_gw_ip" ] && __NLAL_gw_ip="`uci -q get network.lan.gateway`"
	echo -n $__NLAL_gw_ip
	[ -n "$__NLAL_gw_ip" ]
}

# check RE ping CAP ret
# return 0: linkup
# return else: no link
mimesh_gateway_ping()
{
	local gw_ip=$(mimesh_get_gw_ip lan)

	if [ -n "$gw_ip" ]; then
		ping $gw_ip -c 1 -w 2 > /dev/null 2>&1
		[ $? -eq 0 ] && return 0
	else
		MIMESH_LOGI "  NO find valid gateway!"
	fi

	return 1
}

# check RE assoc CAP ret
# return 0: associated
# return else: no assoc
mimesh_re_assoc_check()
{
	local iface_5g_bh=$(uci -q get misc.backhauls.backhaul_5g_sta_iface)
	[ -z "$iface_5g_bh" ] && iface_5g_bh="wl01"

	wpa_cli -p /var/run/wpa_supplicant-$iface_5g_bh list_networks | grep -wq "CURRENT"
	[ $? -eq 0 ] && return 0

	mimesh_gateway_ping

	return $?
}

mimesh_cap_bh_check()
{
	local iface_5g_bh=$(uci -q get misc.backhauls.backhaul_5g_ap_iface)
	[ -z "$iface_5g_bh" ] && iface_5g_bh="wl5"
	cfg80211tool $iface_5g_bh get_backhaul | grep -wq "get_backhaul:1"

	return $?
}
