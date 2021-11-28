#!/bin/sh

logf=/tmp/log/hyd-lan.log
__restart()
{
    killall hyd
    /etc/init.d/hyd stop
    /etc/init.d/hyfi-bridging start

    sleep 1
    rm -rf $logf
    DBG_APPEND_FILE_PATH=$logf  /usr/sbin/hyd -d -C /tmp/hyd-lan.conf -P 7777 &

}


__set_dbg_level()
{

    list="$1"
    lvl="$2"

    echo " set hyd module $list to level $lvl"

    for mod in $list; do
        (sleep 1; echo dbg level $mod $lvl; sleep 1; echo q) | telnet 127.0.0.1 7777
    done

}


__usage()
{
    echo " $0 help:"
    echo "   $0 r : restart hyd with debug env log to $logf"
    echo "   $0 dbg mods level: set hyd module debug levels"
    echo "      module: plcManager psService heService bandmon hyif ...."
    echo "      level: dump debug info err none "
}


case "$1" in
    r|restart)
        __restart
        ;;
    dbg)
        list="$2"
        [ -z "$list" ] && (__usage; exit 1)
        lvl="$3"
        [ -z "$lvl" ] && lvl=debug

        __set_dbg_level "$list" "$lvl"
        ;;
    *)
        __usage
esac


