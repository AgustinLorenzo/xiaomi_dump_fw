#!/bin/sh
is_dev_encry()
{
	dev=$1
	if [ x"$dev" == x"" ]; then
		return 1
	fi
	
	for i in $(seq 0 10)
	do
		dev_tmp=`uci -q get wireless.@wifi-iface[$i].ifname`
		#printf "%d - %s - %s - %s\n" $i $dev_tmp $encryption $dev
		if [ x"$dev_tmp" = x"$dev" ]; then
			encryption=`uci -q get wireless.@wifi-iface[$i].encryption`
			#printf "%d - %s - %s - %s\n" $i $dev_tmp $encryption $dev
			if [ x"$encryption" != x"none" ]; then
				return 1
			else
				return 0
			fi
		fi
	done	
	return 1
}

[ x"${STA}" != x"" ] && {
	netmode=`uci -q get xiaoqiang.common.NETMODE`
    if [ x"$netmode" = x ]; then
	    BUS="ubus"
	else
        ROUTER_IP=`uci get network.lan.gateway`
        BUS="tbus -h $ROUTER_IP -p 784"
	fi
	    
	is_dev_encry $DEVNAME
	authorize=$?
	if [ x"$ACTION" = x"AUTHORIZE" -a x"$authorize" = x"1" ]; then
		$BUS send trafficd '{"iwevent":{"hw":"'$STA'","ifname":"'$DEVNAME'","type":1}}'
	elif [ x"$ACTION" = x"ASSOC" -a x"$authorize" != x"1" ]; then
		$BUS send trafficd '{"iwevent":{"hw":"'$STA'","ifname":"'$DEVNAME'","type":1}}'
	elif [ x"$ACTION" = x"DISASSOC" ]; then
		$BUS send trafficd '{"iwevent":{"hw":"'$STA'","ifname":"'$DEVNAME'","type":0}}'
	fi
}	
		
