#!/bin/sh
# Copyright (C) 2014 Xiaomi

#TODO:
#  R1CM
#    6 未打开wifi则需要打开wifi
#    12 root ap设置变化检测
#
#  R1D
#    1 扫描的结果太少，修改为全部的列表
#    2 WIFI AP中继参数下发不到驱动的问题
#    3 加密/多种场景的问题
#    4 路由-中继-路由 这个顺序执行后会出现收到本网卡地址的错误
#
#
. /lib/functions.sh

[ -f /usr/sbin/wifiap_platform.sh ] || exit 1

. /usr/sbin/wifiap_platform.sh

SCRIPT_FILENAME=$0

wifiap_usage()
{
    echo "usage: $SCRIPT_FILENAME OBJECT"
    echo "    step 1: $SCRIPT_FILENAME connect ROOT_AP_SSID ROOT_AP_PASSWORD"
    echo "        if success(exit 0), it connected to ROOT AP, then try step 2. if fail(exit 1), retry step 1."  
    echo "        "  
    echo "    step 2: $SCRIPT_FILENAME open"
    echo "        complete wifiap setup after connect to ap(step 1)."
    echo "        if success(exit 0), wifi ap works. if fail(exit 1), it will back to router mode."
    echo "    step 3: $SCRIPT_FILENAME close"
    echo "        close wifiap mode."
    echo "        "
}

######################################################################
#       Virtual Interface abstract for ap
#    scan   :  scan wifi list nearby, and output in json format
#    connect:  try connect to the given ssid, if success, get the manage ip
#    open   :  backup config, set lan/wifi 
#    close  :  recover config.
######################################################################

#virtual interface abstract for different plantform
# ap scan

wifiap_scan()
{
    wifiap_logger "wifiap mode try connect."

    eval wifiap_scan_process "$1"  "$2"

    return 0
}

#virtual interface abstract for different plantform
# ap connect
wifiap_connect() 
{
    wifiap_logger "wifiap mode try connect."

    eval wifiap_connect_process "$1"  "$2"
 
    return 0
}

#virtual interface abstract for different plantform
# ap open
wifiap_open() 
{
    wifiap_logger "wifiap mode try open."

    #if not apmode, backup all relate configs
    
    wifiap_parameter_restore
    [ $? != '0' ] && return 1;
    
    wifiap_logger "ssid:$encaped_ssid open."

    [ apmode != "wifiapmode" ] && wifiap_config_backup

    eval wifiap_open_process "$1"  "$2"

    [ $? != '0' ] && return 1;

    return 0
}

#virtual interface abstract for different plantform
# ap close
wifiap_close() 
{
    wifiap_logger "wifiap mode try close."

    wifiap_config_recover

uci -q batch <<-EOF >/dev/null
    delete xiaoqiang.common.NETMODE
    commit xiaoqiang
EOF

    sleep 3;

    eval wifiap_close_process

    wifiap_logger "wifiap mode close finish."

    return 0;

}

OPT=$1

#main
case $OPT in 
    scan)
        wifiap_scan "$2" 1>/dev/null 2>/dev/null
        wifiap_scan_output
    ;;

    connect) 
        wifiap_connect "$2" "$3"
        return $?
    ;;

    open) 
        wifiap_open 
        return $?
    ;;

    close) 
        wifiap_close
        return $?
    ;;

    * ) 
        wifiap_usage
        return 0
    ;;
esac


