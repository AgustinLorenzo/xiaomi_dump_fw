#!/bin/sh

ifname_prefix=${IFNAME:0:2}
if [ "x$ifname_prefix" == "xwl" ]; then
    #EVENT 0-offline, 1-online
    if [ "x$EVENT" == "x1" ] || [ "x$EVENT" == "x3" ]; then
        /usr/sbin/miqosc device_in $MAC
    fi

    if [ "x$EVENT" == "x0" ]; then
        /usr/sbin/miqosc device_out $MAC
    fi
fi

if [ "x$ifname_prefix" == "xet" ]; then
    #EVENT 0-offline, 1-online
    if [ "x$EVENT" == "x1" ] || [ "x$EVENT" == "x3" ]; then
        /usr/sbin/miqosc device_in 00
    fi

    if [ "x$EVENT" == "x0" ]; then
        /usr/sbin/miqosc device_out 00
    fi
fi
