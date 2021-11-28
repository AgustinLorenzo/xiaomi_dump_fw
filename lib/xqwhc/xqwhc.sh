#!/bin/sh

## shell lib for xqwhc, also provide syncrinize with qca-self son

######### begin xqwhc sync with repacd
# to let xqwhc know iface may bring down in repacd state, avoid conflict
#  iface down by repacd must be brought up ONLY by repacd
XQWHC_REPACD_SYNC="/tmp/run/xqwhc_repacd_sync"
XQWHC_REPACD_SYNC_LOCK="/tmp/lock/xqwhc_repacd_sync.lock"
XQWHC_REPACD_IFDOWN="repacd_force_down"

xqwhc_repacd_sync()
{
    local state="$1"
    local val="$2"

    local ts=`date +%Y%m%d-%H%M%S`
    sed "/${state}:/d" -i $XQWHC_REPACD_SYNC
    echo "$ts ${state}:$val" >> $XQWHC_REPACD_SYNC
    sync
    return 0
}

xqwhc_repacd_sync_lock()
{
    [ "$1" = "lock" ] && {
        arg=""
    } || {
        arg="-u"
    }   

    lock "$arg" ${XQWHC_REPACD_SYNC_LOCK}_$2
}
######### end xqwhc sync with repacd





