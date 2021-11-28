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
    is_dev_encry $DEVNAME
    authorize=$?
    if [ x"$netmode" = x -o x"$netmode" = x"whc_cap" -o x"$netmode" = x"dmzsimple" -o x"$netmode" = x"dmzmode" ]; then
	BUS="ubus"
    else
	ROUTER_IP=`uci get network.lan.gateway`
	BUS="tbus -h $ROUTER_IP -p 784"
	STA_UPPER=`echo ${STA} | awk '{print toupper($0)}'`
	STA_IP= `cat /proc/net/arp | grep ${STA} | awk '{print $1}'`
	[ x"$STA_IP" = x"" ] && STA_IP="0.0.0.0"
	#中继模式下由于使用xiaoqiang_sync.lua上报当前在线设备,由于未做监听,所以下线无法立即通知服务器,从而导致需要服务器超时设备才展示离线.实时性不高.所以下线后在这里通知服务器.
	#XP-25391
	if [ x"$ACTION" = x"DISASSOC" ]; then
	    matool --method reportEvents --params '[{"mac":"'${STA_UPPER}'","eventID":0,"ip":"","payload":""}]'
	    #logger -t "notify_trafficd" -p 1 'matool --method reportEvents --params mac:'${STA_UPPER}''
	elif [ x"$ACTION" = x"AUTHORIZE" -a x"$authorize" = x"1" ]; then
	    matool --method reportEvents --params '[{"mac":"'${STA_UPPER}'","eventID":1,"ip":"'${STA_IP}'","payload":"{\"onlineTime\":0,\"dev\":\"'${DEVNAME}'\",\"mac\":\"'${STA_UPPER}'\",\"ip\":\"'${STA_IP}'\"}"}]'
	    #logger -t "notify_trafficd" -p 1 'matool --method reportEvents --params mac:'${STA_UPPER}' ip:'${STA_IP}''
	elif [ x"$ACTION" = x"ASSOC" -a x"$authorize" != x"1" ]; then
	    matool --method reportEvents --params '[{"mac":"'${STA_UPPER}'","eventID":1,"ip":"'${STA_IP}'","payload":"{\"onlineTime\":0,\"dev\":\"'${DEVNAME}'\",\"mac\":\"'${STA_UPPER}'\",\"ip\":\"'${STA_IP}'\"}"}]'
	    #logger -t "notify_trafficd" -p 1 'matool --method reportEvents --params mac:'${STA_UPPER}' ip:'${STA_IP}''
	fi
    fi

    if [ x"$ACTION" = x"AUTHORIZE" -a x"$authorize" = x"1" ]; then
	$BUS send trafficd '{"iwevent":{"hw":"'$STA'","ifname":"'$DEVNAME'","type":1}}'
    elif [ x"$ACTION" = x"ASSOC" -a x"$authorize" != x"1" ]; then
	$BUS send trafficd '{"iwevent":{"hw":"'$STA'","ifname":"'$DEVNAME'","type":1}}'
    elif [ x"$ACTION" = x"DISASSOC" -o x"$ACTION" = x"BLACKLISTED" ]; then
	$BUS send trafficd '{"iwevent":{"hw":"'$STA'","ifname":"'$DEVNAME'","type":0}}'
    fi
}

