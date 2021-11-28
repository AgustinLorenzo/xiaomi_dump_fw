#!/bin/sh
# Copyright (C) 2015 Xiaomi
#

. /lib/functions.sh
section_cb(){
    config_get device $1 device
    if [ x$device = x$device_name ]
    then
	echo $1
	return
    fi
}
wifiap_interface_find_by_device()
{
    config_load wireless
    config_foreach section_cb wifi-iface
}

#default interface num 1
#2.4G interface setup
device_name=`uci get misc.wireless.if_2G`
iface_no=`wifiap_interface_find_by_device $device_name`
[ "$iface_no" == "" ] && return 1

maclist="`uci -q get wireless.$iface_no.maclist`"
maclist_format="`echo -n $maclist | sed "s/ /;/g"`"
filter="`uci -q get wireless.$iface_no.macfilter`"

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

tbus -t 2 list | grep -v netapi | grep -v master | while read a
do
    if [ "$HARDWARE" == "D01" ]; then
        if [ "$level" != "" -a  "$auth" != "" ]; then
            logger -p info -t maclist "set both auth:$auth level:$level"
            tbus -t 2 call $a access  "{\"policy\":${policy},\"list\":\"${maclist_format}\",\"level\":${level},\"auth\":${auth}}"
        elif [ "$level" != "" ]; then
            logger -p info -t maclist "set only level:$level"
            tbus -t 2 call $a access  "{\"policy\":${policy},\"list\":\"${maclist_format}\",\"level\":${level}}"
        elif [ "$auth" != "" ]; then
            logger -p info -t maclist "set only auth:$auth"
            tbus -t 2 call $a access  "{\"policy\":${policy},\"list\":\"${maclist_format}\",\"auth\":${auth}}"
        else
            #call tbus function to notice device change maclist
            tbus -t 2 call $a access  "{\"policy\":${policy},\"list\":\"${maclist_format}\"}"
        fi
    else
        #call tbus function to notice device change maclist
        tbus -t 2 call $a access  "{\"policy\":${policy},\"list\":\"${maclist_format}\"}"
    fi
done

