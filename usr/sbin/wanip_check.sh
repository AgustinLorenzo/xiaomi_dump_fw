#!/bin/sh
# Copyright (C) 2015 Xiaomi
wanip_status="/tmp/router_in_xiaomi"

max_retry=30
interval=10
#max_retry= "$1"    # if ping failed or matool failed, retry times.
#interval="$2"     # interval for every check.

guest_usage()
{
    echo "$0:"
    echo "    open: start guest wifi, delete all config"
    return;
}


wanip_check_log()
{
    logger -p debug -t wifi_wanip_check "$1"
}

#wifi
#guest_2G="$(uci get wireless.${network_name}_2G 2>/dev/NULL)"


# parse json code
parse_json()
{
    ### {"code":0,"data":{"flag":1}}
    echo "$1" | awk -F "$2" '{print$2}'|awk -F "" '{print $3}'
}

# check if we are in xiaomi net.
# return 0: not in xiaomi
# return 1: in xiaomi
# return 2: check failed, api.miwfi.com unreachble or matool failed.
check_wanip_status()
{
    # wait 5s, check if api.miwifi.com ping OK ?
    ping api.miwifi.com -c 3 -w 5 > /dev/null 2>&1
    if [ $? != 0 ]
    then
        wanip_check_log "ping api.miwifi.com failed, check later !"
        return 2;
    else
        wanip_check_log "ping api.miwifi.com ok, do check !"
    fi;

    # get default MAC
    wan_eth="$(uci get network.wan.ifname 2>/dev/NULL)"
    wanip_check_log "wan_eth: $wan_eth"
    wan_mac="$(ifconfig $wan_eth | grep HWaddr |awk -F ' ' '{print $5}')"
    wanip_check_log "wan_mac: $wan_mac"
    # get SN
    sn="$(nvram show | grep SN | awk -F "=" '{print $2}')"
    wanip_check_log "SN: $sn"

    # get wan status from api.miwifi.com
    wanip_check_log "send cmd: matool --method api_call --params /device/auth_check {\"mac\":\"$wan_mac\",\"sn\":\"$sn\"}"
    auth_status="$(matool --method api_call --params /device/auth_check {\"mac\":\"$wan_mac\",\"sn\":\"$sn\"})"
    wanip_check_log "server ret: $auth_status"

    #echo {"code":0,"data":{"flag":1}} | awk -F "flag:" '{print$2}'|awk -F "" '{print$1}'
    result=$(parse_json $auth_status "flag")
    wanip_check_log "wifishare get wanip in_xiaomi=$result"

    if [ $result == 0 ]; then
        echo "result == 0"
        return 0;
    elif [ $result == 1 ]; then
        echo "result == 1"
        return 1;
    else
        wanip_check_log $auth_status
        return 2;
    fi
}


# check router whether in xiaomi office, for guest wifi.
wanip_check()
{
    #guest_ip="$(uci get network.guest.ipaddr 2>/dev/NULL)"
    #lan_ip="$(uci get network.lan.ipaddr 2>/dev/NULL)"
    #echo $guest_ip
    #echo $lan_ip

    # stop wanip check logic first.
    wanip_check_stop

    wanip_check_log "max_retry: $max_retry"
    wanip_check_log "interval(s): $interval"

    # set flag in xiaomi first.
    echo 1 > $wanip_status

    # do wan ip check
    while [ $max_retry -gt 0 ]
    do
        # get wan status. check only when wan up
        wan_up="$(ubus call network.interface.wan status |grep \"up\"|grep true)"
        if [ "$wan_up" != "" ]
        then
            wanip_check_log "wan is up, we can do check."
            check_wanip_status
            ret="$?"
            wanip_check_log "check_wanip_status: ret = $ret"
            if [ $ret == 0 ]; then
                echo 0 > $wanip_status
                #cat $wanip_status
                break;
            elif [ $ret == 1 ]; then
                echo 1 > $wanip_status
                #cat $wanip_status
                break;
            else
                echo 1 > $wanip_status
                sleep $interval
                let max_retry--
                wanip_check_log "wan is up, server response error, retry $max_retry"
            fi
        else
            sleep $interval
            let max_retry--
            wanip_check_log "wan is down, retry $max_retry"
        fi
    done
}


# kill all check script
wanip_check_stop()
{
    this_pid=$$
    one_pid=""
    _pid_list=""

    _pid_list=$(ps w|grep wanip_check.sh|grep -v grep |grep -v counting|awk '{print $1}')
    for one_pid in $_pid_list
    do
        echo "get wanip check pid "$one_pid" "
        [ "$one_pid" != "$this_pid" ] && {
            echo "wanip check kill "$one_pid
            kill -9 $one_pid
        }
    done
    wanip_check_log "wanip check stop ok."
}

# main
#wanip_check

OPT=$1

wanip_check_log "$OPT"

case $OPT in
    on)
        wanip_check
        return $?
    ;;

    off)
        wanip_check_stop
        return $?
    ;;
esac
