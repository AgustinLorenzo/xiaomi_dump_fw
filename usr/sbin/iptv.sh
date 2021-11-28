#!/bin/sh
# Copyright (C) 2015 Xiaomi

iptv_interface="eth0.3"

iptv_usage()
{
    echo "usage:"
    echo "    $0 [open|close|ifup|ifdown]"
}

iptv_open()
{
uci -q batch <<-EOF >/dev/null
    del network.iptv

    set network.iptv=interface
    set network.iptv.proto=dhcp
    set network.iptv.ifname=${iptv_interface}
    set network.
    commit network


    del firewall.iptv_zone
    del firewall.iptv_igmp
    del firewall.iptv_multicast
    del firewall.iptv_forward

    set firewall.iptv_zone=zone
    set firewall.iptv_zone.name=iptv
    set firewall.iptv_zone.network=iptv
    set firewall.iptv_zone.input=REJECT
    set firewall.iptv_zone.output=ACCEPT
    set firewall.iptv_zone.forward=REJECT
    set firewall.iptv_zone.masq=1
    set firewall.iptv_zone.mtu_fix=1

    set firewall.iptv_igmp=rule
    set firewall.iptv_igmp.name=alow-iptv-igmp
    set firewall.iptv_igmp.src=iptv
    set firewall.iptv_igmp.proto=igmp
    set firewall.iptv_igmp.dest_port=ACCEPT

    set firewall.iptv_multicast=rule
    set firewall.iptv_multicast.name=allow-iptv-multicast
    set firewall.iptv_multicast.src=iptv
    set firewall.iptv_multicast.proto=udp
    set firewall.iptv_multicast.dest=lan
    set firewall.iptv_multicast.dest_ip=224.0.0.0/4
    set firewall.iptv_multicast.target=ACCEPT
    set firewall.iptv_multicast.family=ipv4

    set firewall.iptv_forward=forwarding
    set firewall.iptv_forward.src=lan
    set firewall.iptv_forward.dest=iptv


    commit firewall
EOF

    /etc/init.d/hwnat stop
    /etc/init.d/hwnat disable

    rmmod hw_nat
    /etc/init.d/network restart
    /etc/init.d/igmpproxy enable
    /etc/init.d/igmpproxy restart
}

iptv_close()
{
uci -q batch <<-EOF >/dev/null
    del network.iptv
    commit network

    del firewall.iptv_forward
    del firewall.iptv_zone
    del firewall.iptv_igmp
    del firewall.iptv_multicast
    commit firewall
EOF
    /etc/init.d/hwnat enable
    /etc/init.d/hwnat start

    /etc/init.d/igmpproxy stop
    /etc/init.d/igmpproxy disable
    /etc/init.d/network restart

    return 0
}

igmp_altnet_add()
{
    local net=$1
    local prefix=$2

    [ -z $net ] && return 0
    [ "$net" == "0.0.0.0" ] && return 0
    [ -z $prefix ] && return 0
    [ "$prefix" == "0" ] && return 0

    uci add_list igmpproxy.@phyint[0].altnet="$net/$prefix"
}

iptv_ifup()
{
    iptv_if="$(uci get network.iptv.ifname 2>/dev/null)"
    route_ranges="$(cat /etc/iptv/route 2>/dev/null)"
    route_gw="$(ubus call network.interface.iptv status | grep nexthop | awk -F"\"" '{print $4}')"

    echo "2"> /proc/sys/net/ipv4/conf/${iptv_if}/force_igmp_version

    route del default dev $iptv_if
    uci del igmpproxy.@phyint[0].altnet

    [ "route_gw" == "" ] && exit 1;

    #iptv iface altnet for igmpproxy
    route_address="$(ubus call network.interface.iptv status | grep address | awk -F"\"" '{if($4!="") print $4 }' |tr -d " " 2>/dev/null)"
    route_mask_prefix="$(ubus call network.interface.iptv status | grep mask |awk -F" |," '{if($2!=0) print $2 }' |tr -d " " 2>/dev/null)"
    route_net=`ipcalc.sh $route_address/$route_mask_prefix |grep NETWORK |cut -d"=" -f 2 |tr -d " " 2>/dev/null`
    igmp_altnet_add $route_net $route_mask_prefix

    #lan iface altnet for igmpproxy
    route_address=`uci get network.lan.ipaddr 2>/dev/null`
    route_mask=`uci get network.lan.netmask 2>/dev/null`
    route_net=`ipcalc.sh $route_address $route_mask |grep NETWORK |cut -d"=" -f 2 |tr -d " " 2>/dev/null`
    route_mask_prefix=`ipcalc.sh $route_address $route_mask |grep PREFIX |cut -d"=" -f 2 |tr -d " " 2>/dev/null`
    igmp_altnet_add $route_net $route_mask_prefix

    for range in $route_ranges
    do
        route_net=`echo $range | cut -d"/" -f 1 |tr -d " " 2>/dev/null `
        route_mask=`echo $range | cut -d"/" -f 2 |tr -d " " 2>/dev/null `
        route_mask_prefix=`ipcalc.sh $route_net $route_mask |grep PREFIX |cut -d"=" -f 2 |tr -d " " 2>/dev/null`

        echo "network:$route_net mask:$route_mask mask_prefix:$route_mask_prefix"

        if [ $route_net!="" -a $route_mask!="" -a $route_mask_prefix!="" ]
        then
            route del -net $route_net netmask $route_mask gw $route_gw
            route add -net $route_net netmask $route_mask gw $route_gw

            igmp_altnet_add $route_net $route_mask_prefix
        fi
    done

    uci commit igmpproxy

    /etc/init.d/igmpproxy restart
}


iptv_ifdown()
{
    iptv_if="$(uci get network.iptv.ifname 2>/dev/null)"
    route_ranges="$(cat /etc/iptv/route 2>/dev/null)"
    route_gw="$(ubus call network.interface.iptv status | grep nexthop | awk -F"\"" '{print $4}' 2>/dev/null)"

    uci del igmpproxy.@phyint[0].altnet

    [ "route_gw" == "" ] && exit 1;

    for range in $route_ranges
    do
        route_net=`echo $range | cut -d"/" -f 1  2>/dev/null `
        route_mask=`echo $range | cut -d"/" -f 2  2>/dev/null `
        route_mask_prefix=`ipcalc.sh $route_net $route_mask |grep PREFIX |cut -d"=" -f 2`

        echo "network:$route_net mask:$route_mask mask_prefix:$route_mask_prefix"

        if [ $route_net!="" -a $route_mask!="" -a $route_mask_prefix!="" ]
        then
            route del -net $route_net netmask $route_mask gw $route_gw
        fi
    done
}


iptv_usage()
{
    echo "usage:"
}

OPT=$1

#main
case $OPT in
    open)
        iptv_open
        return $?
    ;;

    close)
        iptv_close
        return $?
    ;;

    ifup)
        #/lib/netifd/dhcp.script setup_interface
        iptv_ifup
        return $?
    ;;

    ifdown)
        iptv_ifdown
        return $?
    ;;

    *)
        iptv_usage
        return 0
    ;;
esac

