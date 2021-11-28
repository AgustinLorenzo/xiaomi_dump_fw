#!/bin/sh

# this script used to transfer debug env to run hyd in taskmonitor
[ -z "$1" -o ! -f "$1" ] && {
	echo " hyd start error, conf invalid!"
	exit 1
}
[ -z "$2" ] && {
	echo " hyd start error, portid invalid!"
	exit 2
}
[ -n "$3" ] && export DBG_APPEND_FILE_PATH="$3"
[ -n "$4" ] && export DBG_LEVELS="$4"

# add exception workaroud, in case br-lan was down/up by other process, we must re attach br-lan to hyctl
[ "`sysctl -n net.bridge.bridge-nf-call-custom`" -gt 1 ] && {
    hyctl show 2>/dev/null | grep -wq "br-lan" || {
        logger -p 1 -t "xqwhc_hyd" " *exception, restart hyfi bridge to exit abnormal"
        /etc/init.d/hyfi-bridging restart
    }
}

/usr/sbin/hyd -d -C "$1" -P "$2" &

