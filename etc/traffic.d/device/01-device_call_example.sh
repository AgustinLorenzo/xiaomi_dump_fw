#!/bin/sh

logger -t trafficd_device_example -p1 "mac:$MAC,type:$TYPE,event:$EVENT,ifname:$IFNAME,is_repeat:$IS_REPEAT,ip:$IP"


#mac:
#	11:22:AA:BB:CC:DD
#type:
#	router
#	ap
#event:
#	0(下线）
#	1(上线）
#	3(ip改变)
#ifname:
#	eth1 eth2 eth3 eth0 wl0 wl1
#is_repeat:
#	0(第一次)
#	1(非第一次)
#ip:
#	192.168.31.1(可能不存在）
