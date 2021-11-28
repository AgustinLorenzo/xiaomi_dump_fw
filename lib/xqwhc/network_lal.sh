#!/bin/sh

# network lowlevel abstract layer for wireless lan wan
. /lib/xqwhc/xqwhc_public.sh

__get_wifi_iface()
{
    local iface network backhaul
    config_get network $1 network
    config_get iface "$1" ifname
    config_get backhaul "$1" backhaul

    if [ -n "$iface" -a "$2" = "$network" -a "$backhaul" -eq 1 ]; then
        append $3 $iface 
    fi
}

__get_wifi_iface_enable()
{
    local iface network en backhaul
    config_get network $1 network
    config_get iface "$1" ifname
    config_get en "$1" disabled '0'
    config_get backhaul "$1" backhaul

    if [ -n "$iface" -a "$2" = "$network" -a "$en" -eq 0 -a "$backhaul" -eq 1 ]; then
        append $3 $iface
    fi
}

__get_wifi_iface_ap()
{
    local iface network mode backhaul
    config_get network $1 network
    config_get iface "$1" ifname
    config_get mode "$1" mode
    config_get backhaul "$1" backhaul

    if [ -n "$iface" -a "$2" = "$network" -a "$mode" = "ap" -a "$backhaul" -eq 1 ]; then
        append $3 $iface
    fi
}

__get_wifi_iface_sta()
{
    local iface network mode
    config_get network $1 network
    config_get iface "$1" ifname
    config_get mode "$1" mode

    if [ -n "$iface" -a "$2" = "$network" -a "$mode" = "sta" ]; then
        append $3 $iface
    fi
}

# get wifi vap&sta __ifaces in network $1
# they are backhauls in theroy, but also depend on the actual hyt td
nlal_get_wifi_iface_bynet()
{
    local __NLAL_netw="$1"
    __NLAL__list=""

    config_load wireless
    config_foreach __get_wifi_iface wifi-iface $__NLAL_netw __NLAL__list

    eval "$2=\"$__NLAL__list\";[ -n \"\${$2}\" ]"
}

nlal_get_wifi_apiface_bynet()
{
    local __NLAL_netw="$1"
    __NLAL__list=""

    config_load wireless
    config_foreach __get_wifi_iface_ap wifi-iface $__NLAL_netw __NLAL__list

    eval "$2=\"$__NLAL__list\";[ -n \"\${$2}\" ]"
}

nlal_get_wifi_staiface_bynet()
{
    local __NLAL_netw="$1"
    __NLAL__list=""

    config_load wireless
    config_foreach __get_wifi_iface_sta wifi-iface $__NLAL_netw __NLAL__list

    eval "$2=\"$__NLAL__list\";[ -n \"\${$2}\" ]"
}

nlal_get_eth_iface_bynet()
{
    local __NLAL_netw="$1"
    __NLAL__list=""

    __NLAL__list="`uci -q get network.${__NLAL_netw}.ifname`"

    eval "$2=\"$__NLAL__list\";[ -n \"\${$2}\" ]"
}

# get all hyfi ifaces in network $1 nomatter enable flag
# include wifi eth
nlal_get_hyfi_ifaces_raw_slow()
{
    . /lib/functions.sh
    . /lib/functions/hyfi-debug.sh
    . /lib/functions/hyfi-network.sh
    . /lib/functions/hyfi-iface.sh

    local __NLAL__list=""

    ## get wifi iface
    local __NLAL__list_raw=""
    hyfi_get_wlan_ifaces_raw $1 __NLAL__list_raw
    # __NLAL__list_raw=ath0:WLAN,ath1:WLAN,ath01:WLAN,ath11:WLAN
    __NLAL__list_raw=`echo $__NLAL__list_raw | sed 's/:WLAN//g' | sed 's/,/ /g'`
    #echo "wifi __ifaces=$__NLAL__list_raw"
    append __NLAL__list "$__NLAL__list_raw"

    ## get eth iface
    local __NLAL__list_eth
    hyfi_get_ether_ifaces $1 __NLAL__list_eth
    # __NLAL__list_raw=eth1:ETHER,eth2:ETHER,eth0:ETHER
    __NLAL__list_eth=`echo $__NLAL__list_eth | sed 's/:ETHER//g' | sed 's/,/ /g'`
    #echo " __ifaces=$__NLAL__list_raw"
    append __NLAL__list "$__NLAL__list_eth"

    eval "$2=\"$__NLAL__list\";[ -n \"\${$2}\" ]"
}

nlal_get_hyfi_ifaces_raw()
{
    local __NLAL_netw="$1"

    local __NLAL__list_raw=""
    local tl_wifi=""
    nlal_get_wifi_iface_bynet $__NLAL_netw tl_wifi
    append __NLAL__list_raw "$tl_wifi"

    local tl_eth=""
    nlal_get_eth_iface_bynet $__NLAL_netw tl_eth
    append __NLAL__list_raw "$tl_eth"

    eval "$2=\"$__NLAL__list_raw\";[ -n \"\${$2}\" ]"
}

# get wireless all __NLAL__iface, only on REs
# $1: network: lan/guest
# $2: sta_list:
nlal_get_wifi_ifaces_all()
{
    . /lib/functions.sh
    . /lib/functions/hyfi-debug.sh
    . /lib/functions/hyfi-network.sh
    . /lib/functions/hyfi-iface.sh

    local __NLAL__list_raw=""
    hyfi_get_wlan_ifaces $1 __NLAL__list_raw
    # __NLAL__list_raw=ath0:WLAN,ath1:WLAN,ath01:WLAN,ath11:WLAN

    __NLAL__list_raw=`echo $__NLAL__list_raw | sed 's/:WLAN//g' | sed 's/,/ /g'`
    #echo "wifi __ifaces=$__NLAL__list_raw"

    eval "$2=\"$__NLAL__list_raw\";[ -n \"\${$2}\" ]"
}

# get wireless sta __NLAL__iface, only on REs
# $1: network: lan/guest
# $2: sta_list: 
nlal_get_sta_ifaces()
{
    local __NLAL__list=""
    local __NLAL__list_all

    nlal_get_wifi_ifaces_all "$1" __NLAL__list_all

    # check __NLAL__iface is sta
    local __NLAL__iface=""
    for __NLAL__iface in $__NLAL__list_all; do
        iwconfig $__NLAL__iface 2>&1 | grep -q "Mode:Managed" && eval "append __NLAL__list $__NLAL__iface"
    done

    eval "$2=\"$__NLAL__list\";[ -n \"\${$2}\" ]"
}



# get wireless AP __NLAL__iface, called on CAP/RE
# $1: network: lan/guest
# $2: ap_list: 
nlal_get_ap_ifaces()
{
    local __NLAL__list=""
    local __NLAL__list_all

    nlal_get_wifi_ifaces_all "$1" __NLAL__list_all

    # check __NLAL__iface is sta
    local __NLAL__iface=""
    for __NLAL__iface in $__NLAL__list_all; do
        iwconfig $__NLAL__iface 2>&1 | grep -q "Mode:Master" && eval "append __NLAL__list $__NLAL__iface"
    done

    eval "$2=\"$__NLAL__list\";[ -n \"\${$2}\" ]"
}


# get wireless sta __NLAL__iface name by freq
# $1: freq 2g/5g
nlal_get_sta_iface()
{
    local __NLAL_type="$1"

    #nlal_get_sta_ifaces $NETWORK_PRIV list

    # get sta ifname from miwifi misc
    if [ "$__NLAL_type" = "2g" ]; then
        __NLAL__iface=`uci -q get misc.backhauls.backhaul_2g_sta_iface`
        [ -z "$__NLAL__iface" ] && __NLAL__iface=wl11
    elif [ "$__NLAL_type" = "5g" ]; then
        __NLAL__iface=`uci -q get misc.backhauls.backhaul_5g_sta_iface`
        [ -z "$__NLAL__iface" ] && __NLAL__iface=wl01
    else
        __NLAL__iface=""
    fi

    eval "$2=$__NLAL__iface"
    return 0
}

nlal_enable_sta_iface()
{
    local __NLAL_ifn="$1"
    wpa_cli -p /var/run/wpa_supplicant-$__NLAL_ifn enable_network 0 >/dev/null 2>&1
}

nlal_disable_sta_iface()
{
    local __NLAL_ifn="$1"
    wpa_cli -p /var/run/wpa_supplicant-$__NLAL_ifn disable_network 0 >/dev/null 2>&1
}

# check wifi sta if is enabled
# 0: enable
# 1: disable
nlal_check_sta_iface()
{
    local __NLAL_ifn="$1"
    ######## use strict pattern,  in case wpa_supplicant set to [TEMP-DISABLED]
    wpa_cli -p /var/run/wpa_supplicant-$__NLAL_ifn list_networks 2>&1 | grep -wq "\[DISABLED\]" && return 1
    return 0
}

nlal_check_wifi_iface_up()
{
    local __NLAL_ifn="$1"
    # add arg2 flag to check if wifi iface up in son state
        
    iwconfig $__NLAL_ifn 2>/dev/null | grep -q -e "Mode:Managed" -e "Mode:Master"
    ret=$?
    if [ -n "$2" ]; then
        iwpriv $__NLAL_ifn get_backhaul | grep -wq "get_backhaul:1"
        ret=$?
    fi  

    return $ret 
}

# generic -- check if wifi sta __NLAL__iface is assoced
# $1 input __NLAL__iface
nlal_check_sta_assoced()
{
    local __NLAL__iface="$1"

    __state=`wpa_cli -i $__NLAL__iface -p /var/run/wpa_supplicant-$__NLAL__iface status 2>/dev/null | awk -F= '/wpa_state/ {print $2}'`

    WHC_LOGD " check_sta $__NLAL__iface state = $__state "

    if [ "$__state" = "COMPLETED" ]; then
        return 0
    fi

    return 1
}

# get eth ifs exclude plc host if
nlal_get_eth_ifaces()
{
    . /lib/functions.sh
    . /lib/functions/hyfi-debug.sh
    . /lib/functions/hyfi-network.sh
    . /lib/functions/hyfi-iface.sh

    local __NLAL__list_raw=""
    hyfi_get_ether_ifaces $1 __NLAL__list_raw
    # __NLAL__list_raw=eth1:ETHER,eth2:ETHER,eth0:ETHER

    __NLAL__list_raw=`echo $__NLAL__list_raw | sed 's/:ETHER//g' | sed 's/,/ /g'`
    #echo " __ifaces=$__NLAL__list_raw"

    eval "$2=\"$__NLAL__list_raw\";[ -n \"\${$2}\" ]"
}

# get wifi sta \eth backhaul __ifaces, only on RE
# they are backhauls in theroy, but also depend on the actual hyt td
nlal_get_bh_ifaces()
{
    . /lib/functions.sh
    . /lib/functions/hyfi-debug.sh
    . /lib/functions/hyfi-network.sh
    . /lib/functions/hyfi-iface.sh

    local __NLAL__list_raw=""
    local __NLAL__list=""

    hyfi_get_wlan_ifaces $1 __NLAL__list_raw
    # list=ath0:WLAN,ath1:WLAN,ath01:WLAN,ath11:WLAN,eth0:ETHER,eth1:PLC


    __NLAL__list_raw=`echo $__NLAL__list_raw | sed 's/:WLAN//g' | sed 's/,/ /g'`
    #echo "wifi __ifaces=$__NLAL__list_raw"

    # check __NLAL__iface is sta
    for __NLAL__iface in $__NLAL__list_raw; do
        #echo $__NLAL__iface
        iwconfig $__NLAL__iface 2>&1 | grep -q "Mode:Managed" && eval "append __NLAL__list $__NLAL__iface"
     done

    eval "$2=\"$__NLAL__list\";[ -n \"\${$2}\" ]"
}

# get son managed bridges, foreach network __NLAL__iface which has option ieee1905managed=1
nlal_get_son_bridges()
{
    . /lib/functions.sh
    . /lib/functions/hyfi-debug.sh
    . /lib/functions/hyfi-network.sh
    . /lib/functions/hyfi-iface.sh

    local __NLAL__br1=""
    local __NLAL__br2=""
    hyfi_get_ieee1905_managed_iface __NLAL__br1 __NLAL__br2
    echo "$__NLAL__br1 $__NLAL__br2";[ -n "$__NLAL__br1" -o -n "$__NLAL__br2" ]
}

# generic -- get wifi sta __NLAL__iface freq
# $1 input __NLAL__iface
# $2 output freq type: 2g 5g
nlal_get_wiface_freq()
{
    local __NLAL__iface="$1"

    __freq=`iwlist $__NLAL__iface channel 2>&1 | grep -e "Current Frequency" | grep -o ".\." | sed 's/\./g/'`

    eval "$2=$__freq"
    return 0
}


# get sta __NLAL__iface  Access Point: bssid
# $1 input __NLAL__iface
# $2 output sta 
nlal_get_sta_ap_bssid()
{
    local __NLAL__iface="$1"
    local __NLAL__bssid=`iwconfig $__NLAL__iface 2>&1 | grep "Access Point:" | grep -E -o "..:..:..:..:..:.."`
    eval "$2=$__NLAL__bssid"
    [ -n "$__NLAL__bssid" ]
}

# generic --- check if self has an eth backhaul
nlal_check_eth_backhaul()
{
    # derive from repacd-run.sh
    # gateway attach to bridge eth __ifaces 
    . /lib/functions.sh
    . /lib/functions/repacd-lp.sh
    . /lib/functions/repacd-gwmon.sh
    __gwmon_check_gateway "$NETWORK_PRIV"
    [ $? -gt 0 ]
}

nlal_get_gw_ip()
{
    local __NLAL_netw="$1"
    local __NLAL_gw_ip="`route -n  | grep "^0.0.0.0" | grep br-$__NLAL_netw | awk '{print $2}' | xargs`"
    [ -z "$__NLAL_gw_ip" ] && __NLAL_gw_ip="`uci -q get network.lan.gateway`"
    echo -n $__NLAL_gw_ip
    [ -n "$__NLAL_gw_ip" ]
}


nlal_get_gw_mac()
{
    local __NLAL_netw="$1"
    local __NLAL_gw_ip=$(nlal_get_gw_ip "$__NLAL_netw")
    local __NLAL_gw_mac=""
    [ -n "$__NLAL_gw_ip" ] && {
        #__NLAL_gw_mac="`arp -n | grep -w "$__NLAL_gw_ip" | grep -Eo "..:..:..:..:..:.."`"
        __NLAL_gw_mac="$(grep -w "$__NLAL_gw_ip" /proc/net/arp | grep -w "$__NLAL_netw" | awk '{print $4}')"
        echo -n "$__NLAL_gw_mac"
    }
    [ -n "$__NLAL_gw_mac" ]
}

nlal_get_gateway_iface()
{
    local __NLAL_netw="$1"

    local __NLAL_gw_ip=$(nlal_get_gw_ip "$__NLAL_netw")
    local __NLAL_gw_mac=$(nlal_get_gw_mac "$__NLAL_netw")
    local __NLAL_gw_brport=""
    local __NLAL_gw_if=""
    [ -n "$__NLAL_gw_mac" ] && {
        __NLAL_gw_brport="`brctl showmacs br-$__NLAL_netw 2>&1 | grep -w "$__NLAL_gw_mac" | awk '{print $1}'`"
        __NLAL_gw_if="`brctl showstp br-$__NLAL_netw 2>&1 | grep -Ew "\($__NLAL_gw_brport\)" | awk '{print $1}'`"
        eval "$2=$__NLAL_gw_if";
    }

    [ -n "$__NLAL_gw_if" ] # || {
    #    WHC_LOGE " gateway can NOT get, with gwip=[$__NLAL_gw_ip], gwmac=[$__NLAL_gw_mac]"
    #    return 1
    #}
}

nlal_if_eth_bh_exist()
{
    local __NLAL_netw="$1"

    local __NLAL_ifn
    nlal_get_gateway_iface $__NLAL_netw __NLAL_ifn || return 1

    local __NLAL_ethbhif=""
    nlal_get_eth_iface_bynet $__NLAL_netw __NLAL_ethbhif

    eval "$2=$__NLAL_ifn"
    list_contains __NLAL_ethbhif $__NLAL_ifn
}




