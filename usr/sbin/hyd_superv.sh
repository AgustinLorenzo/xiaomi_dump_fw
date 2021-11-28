#!/bin/sh

# hyd supervisor script

# hyd task and log rotate


HYD_LOG_DIR="/tmp/log"
MAX_LOG_SIZE=3000000


# only used hyd not launch by taskmonitor
task_superv()
{
    [ "`uci -q get hyd.config.Enable`" != "1" ] && return 0

    # check if hyd task running? 
    pidof hyd >/dev/null 2>&1 || {
        logger -p 1 -t "hyd_xqwhc_supperv" " ** hyd task not running, re run it **"
        export DBG_APPEND_FILE_PATH="/tmp/log/hyd-lan.log"
        /usr/sbin/hyd -d -C /tmp/hyd-lan.conf -P 7777 &
    }
}

log_superv()
{
    local list=`ls $HYD_LOG_DIR/hyd-*.log 2>/dev/null`
   
    # if log file exceed size, then gzip it
    for ff in $list; do
        [ "`stat -c%s $ff`" -gt $MAX_LOG_SIZE ] && {
            cd $HYD_LOG_DIR
            # get idx
            idx=$(ls -l $HYD_LOG_DIR | grep "`basename $ff`.[0-9].tar.gz" -c)
            [ "$idx" -gt 9 ] && idx=0
            ffn="`basename $ff`.$idx"
            cp $ff $ffn
            #rm -f `basename $ffn`.tar
            tar -cf $ffn.tar $ffn
            gzip -f $ffn.tar
            rm -f $ffn.tar $ffn
            echo > $ff
            logger -p 1 -t "hyd_xqwhc_superv" " ** `basename ${ff%.log}` log gzip and new create **  "
        }
    done
}



while true; do

    #task_superv
    #log_superv  # move to xqwhc_superv
    sleep 6
done


