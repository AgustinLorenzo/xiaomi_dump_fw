#!/bin/sh
# Copyright (C) 2015 Xiaomi
#

wifiap_interface_find_by_device()
{
    local iface_no_list=""

    iface_no_list=`uci show wireless | awk 'BEGIN{FS="\n";}{for(i=0;i<NF;i++) { if($i~/wireless.@wifi-iface\[.\].device='$1'/) print substr($i, length("wireless.@wifi-iface[")+1, 1)}}'`

    for i in $iface_no_list
    do
        if [ `uci get wireless.@wifi-iface[$i].mode` == "ap" ]
        then
            echo $i
            return 0
        fi
    done

    return 1
}

#default interface num 1
#2.4G interface setup
device_name=`uci get misc.wireless.if_2G`
iface_no=`wifiap_interface_find_by_device $device_name`
[ "$iface_no" == "" ] && return 1

maclist="`uci -q get wireless.@wifi-iface[$iface_no].maclist`"
maclist_format="`echo -n $maclist | sed "s/ /;/g"`"
filter="`uci -q get wireless.@wifi-iface[$iface_no].macfilter`"

# add for D01, use new method
auth="`uci -q get devicelist.settings.auth`"
level="`uci -q get devicelist.settings.level`"
HARDWARE=`/sbin/uci get /usr/share/xiaoqiang/xiaoqiang_version.version.HARDWARE`

if [ "$filter" = "deny" ]; then
    policy=2
elif [ "$filter" = "allow" ]; then
    policy=1
else
    policy=0
fi

tbus list | grep -v netapi | grep -v master | while read a
do
    if [ "$HARDWARE" == "D01" ]; then
        if [ "$level" != "" -a  "$auth" != "" ]; then
            logger -p info -t maclist "set both auth:$auth level:$level"
            timeout -t 2 tbus call $a access  "{\"policy\":${policy},\"list\":\"${maclist_format}\",\"level\":${level},\"auth\":${auth}}"
        elif [ "$level" != "" ]; then
            logger -p info -t maclist "set only level:$level"
            timeout -t 2 tbus call $a access  "{\"policy\":${policy},\"list\":\"${maclist_format}\",\"level\":${level}}"
        elif [ "$auth" != "" ]; then
            logger -p info -t maclist "set only auth:$auth"
            timeout -t 2 tbus call $a access  "{\"policy\":${policy},\"list\":\"${maclist_format}\",\"auth\":${auth}}"
        else
            #call tbus function to notice device change maclist
            timeout -t 2 tbus call $a access  "{\"policy\":${policy},\"list\":\"${maclist_format}\"}"
        fi
    else
        #call tbus function to notice device change maclist
        timeout -t 2 tbus call $a access  "{\"policy\":${policy},\"list\":\"${maclist_format}\"}"
    fi
done

