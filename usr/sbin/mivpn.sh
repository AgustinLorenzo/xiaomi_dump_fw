#!/bin/sh

vpn_debug(){
    logger -p info -t vpn "$1"
}

mivpn_usage(){
    echo "usage: ./mivpn.sh on|off"
    echo "value: on  -- enable mivpn"
    echo "value: off -- disable mivpn"
    echo "note:  mivpn only used when vpn is UP!"
    echo ""
}

setMiVpnOff(){
	#if boot not finish, don't add vpn route until it finished
	bootcheck=$( cat /proc/xiaoqiang/boot_status )
	[ "$bootcheck" == "3" ] || return
	
	trafficall=$(uci get network.vpn.trafficall 2>/dev/null);
	[ "$trafficall" == "yes" ] && return
	
	vpnproto=$(uci get network.vpn.proto 2>/dev/null);
	
	. /lib/functions/network.sh
	
	vpn_debug "ip rule del table vpn."
	ip rule del table vpn
	while [[ $? == 0 ]]; do
		vpn_debug "ip rule retry del table vpn."
		ip rule del table vpn
	done	
	
	network_is_up vpn
	[ $? == 0 ] && {	
		vpn_debug "send traffic to vpn except local, dev $DEVICE to vpn"
		ip route add to 0/0 dev ${vpnproto}-vpn table vpn
		
		network_get_dnsserver dnsservers vpn
		for dnsserver in $dnsservers; do
			vpn_debug "add $dnsserver to vpn"
			ip rule add to $dnsserver table vpn
		done

		network_get_dnsserver dnsservers wan
		for dnsserver in $dnsservers; do
			vpn_debug "add $dnsserver to vpn"
			ip rule add to $dnsserver table vpn
		done
		
		vpn_debug "add $subnet to vpn"	
		network_get_subnet subnet lan
		ip rule add from $(fix_subnet $subnet) table vpn
	}
	
	vpn_debug "delete default proto for ${vpnproto}-vpn."
	ip route del default dev ${vpnproto}-vpn 2>/dev/null

	_nexthop=$(ubus call network.interface.wan status |jason.sh -b | awk '{if($1~/route\",0,\"nexthop/) {nexthop=$2; gsub(/^ *"|\" *$/,"", nexthop); printf("%s",nexthop); return} }' 2>/dev/null)
	[ -z $_nexthop ] && return
	
	wanproto=$(uci get network.wan.proto 2>/dev/null);
	wan_device=$(uci get network.wan.ifname 2>/dev/null);
	[ "$wanproto" == "pppoe" ] && wan_device="pppoe-wan"
	[ -z $wan_device ] && wan_device="eth1"
	
	ip route del default dev $wan_device
	ip route del default dev $wan_device metric 50

	hasdefaultroute=$(route -n | awk -v _nexthop=$_nexthop '{if($1=="0.0.0.0" && $2==_nexthop && $5=="0")  { printf("yes") ; exit;}; }' 2>/dev/null)
	[ "$hasdefaultroute" != "yes" ] && { 
		vpn_debug "add default route gateway $_nexthop."
		route add -net 0.0.0.0 netmask 0.0.0.0 gw $_nexthop metric 0 
	}

	hasdefaultroute=$(route -n | awk -v _nexthop=$_nexthop '{if($1=="0.0.0.0" && $2==_nexthop && $5=="50")  { printf("yes") ; exit;}; }' 2>/dev/null)
	[ "$hasdefaultroute" != "yes" ] && {
		vpn_debug "add default route gateway $_nexthop metric 50."
		route add -net 0.0.0.0 netmask 0.0.0.0 gw $_nexthop metric 50
	}
	
	hasdefaultroute=$(route -n | awk -v _nexthop=$_nexthop '{if($1=="0.0.0.0" && $2==_nexthop && $5=="0")  { printf("yes") ; exit;}; }' 2>/dev/null)
	[ "$hasdefaultroute" != "yes" ] && { 
		vpn_debug "add default route gateway dev $wan_device."
		ip route add default dev $wan_device metric 0
	}

	hasdefaultroute=$(route -n | awk -v _nexthop=$_nexthop '{if($1=="0.0.0.0" && $2==_nexthop && $5=="50")  { printf("yes") ; exit;}; }' 2>/dev/null)
	[ "$hasdefaultroute" != "yes" ] && {
		vpn_debug "add default route gateway dev $wan_device metric 50."
		ip route add default dev $wan_device metric 50
	}
		
	ip route flush cache
}

setMiVpnOn(){
	#if boot not finish, don't add vpn route until it finished
	bootcheck=$( cat /proc/xiaoqiang/boot_status )
	[ "$bootcheck" == "3" ] || return

	trafficall=$(uci get network.vpn.trafficall 2>/dev/null);
	[ "$trafficall" == "yes" ] || return
	
	. /lib/functions/network.sh
	
	#send all traffic to vpn
	wanproto=$(uci get network.wan.proto 2>/dev/null);
	wan_device=$(uci get network.wan.ifname 2>/dev/null);
	vpnproto=$(uci get network.vpn.proto 2>/dev/null);
	[ "$wanproto" == "pppoe" ] && wan_device="pppoe-wan"
	[ -z $wan_device ] && wan_device="eth4"
	vpn_debug "proto=$vpnproto, trafficall=$trafficall, wan_device=$wan_device."
	
	vpn_debug "ip rule del table vpn."
	ip rule del table vpn
	while [[ $? == 0 ]]; do
		vpn_debug "ip rule retry del table vpn."
		ip rule del table vpn
	done
	
	ip route del to 0/0 dev ${vpnproto}-vpn table vpn
	
	network_is_up vpn
	[ $? == 0 ] && {	
		network_get_dnsserver dnsservers vpn
		for dnsserver in $dnsservers; do
			vpn_debug "add $dnsserver to vpn"
			ip rule add to $dnsserver table vpn
		done	

		network_get_dnsserver dnsservers wan
		for dnsserver in $dnsservers; do
			vpn_debug "add $dnsserver to vpn"
			ip rule add to $dnsserver table vpn
		done	

		vpn_debug "add default proto for ${vpnproto}-vpn."
		ip route add default dev ${vpnproto}-vpn
		
		_nexthop=$(ubus call network.interface.wan status |jason.sh -b | awk '{if($1~/route\",0,\"nexthop/) {nexthop=$2; gsub(/^ *"|\" *$/,"", nexthop); printf("%s",nexthop); return} }' 2>/dev/null)
		vpn_debug "send all traffic to vpn, dev ${vpnproto}-vpn to vpn, wan_device=$wan_device, _nexthop=$_nexthop"

		[ -z $_nexthop ] && {
			vpn_debug "nexthop not exist, add default."
			ip route del default dev $wan_device
			ip route del default dev $wan_device metric 50
			ip route add default dev ${vpnproto}-vpn
			ip route flush cache
		}

		hasdefaultroute=$(route -n | awk -v _nexthop=$_nexthop '{if($1=="0.0.0.0" && $2==_nexthop && $5=="0")  { printf("yes") ; exit;}; }' 2>/dev/null)
		while [ "$hasdefaultroute" == "yes" ]
		do
			vpn_debug "remove $wan_device default route."
			ip route del default dev $wan_device
			hasdefaultroute=$(route -n | awk -v _nexthop=$_nexthop '{if($1=="0.0.0.0" && $2==_nexthop && $5=="0")  { printf("yes") ; exit;}; }' 2>/dev/null)
		done

		hasdefaultroute=$(route -n | awk -v _nexthop=$_nexthop '{if($1=="0.0.0.0" && $2==_nexthop && $5=="50")  { printf("yes") ; exit;}; }' 2>/dev/null)
		while [ "$hasdefaultroute" == "yes" ]
		do
			vpn_debug "remove $wan_device default route metric 50."
			ip route del default dev $wan_device metric 50
			hasdefaultroute=$(route -n | awk -v _nexthop=$_nexthop '{if($1=="0.0.0.0" && $2==_nexthop && $5=="50")  { printf("yes") ; exit;}; }' 2>/dev/null)
		done

		ip route flush cache
	}
}

OPT=$1
vpn_lock="/var/run/vpn.lock"
trap "lock -u $vpn_lock; exit 1" SIGHUP SIGINT SIGTERM
lock $vpn_lock

#main
case $OPT in
    on)
        setMiVpnOn
        lock -u $vpn_lock
        return $?
    ;;

    flush)
        setMiVpnOff
        setMiVpnOn
        lock -u $vpn_lock
        return $?
    ;;
    off)
        setMiVpnOff
        lock -u $vpn_lock
        return $?
    ;;

    *)
        mivpn_usage
        lock -u $vpn_lock
        return 1
    ;;
esac
