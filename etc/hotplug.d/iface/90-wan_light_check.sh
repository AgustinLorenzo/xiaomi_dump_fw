#!/bin/sh
#logger -p notice -t "hotplug.d" "90-wan_light_chech.sh: run because of $INTERFACE $ACTION"


if [ "$INTERFACE" = "wan" ]; then
    [ "$ACTION" = "ifdown" -o "$ACTION" = "ifup" ] && {
        /usr/sbin/wan_check.sh reset &
    }
fi
