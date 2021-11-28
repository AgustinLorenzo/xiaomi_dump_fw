#!/bin/sh
# Copyright (C) 2015 Xiaomi
#

HARDWARE=`/sbin/uci get /usr/share/xiaoqiang/xiaoqiang_version.version.HARDWARE`
JSON_TOOL="/usr/sbin/parse_json"

my_usage()
{
    echo "$0:"
    echo "RE get msg form cap and parse msg do action."
    return;
}

re_do_action_log()
{
    logger -s -p info -t action "$1"
}

parse_json(){  
    value=`echo $1  | sed 's/.*'$2':\([^},]*\).*/\1/'`
    echo $value | sed 's/\"//g'
}

do_sync_time()
{
    timezone=$($JSON_TOOL  "$DATA_MSG" "timezone")
    index=$($JSON_TOOL  "$DATA_MSG" "index")
    tz_value=$($JSON_TOOL  "$DATA_MSG" "tz_value")
    re_do_action_log "=============== timezone: $timezone"
    re_do_action_log "=============== index: $index"
    re_do_action_log "=============== tz_value: $tz_value"

    # save timezone
    if [ "$timezone" != "" ]; then
        if [ "$index" != "" ]; then
            uci set system.@system[0].timezone=$timezone
            uci set system.@system[0].timezoneindex=$index
            uci commit system
            # write timezone to dist file
            echo "$tz_value" > /tmp/TZ
        fi
    fi

    # save time and date, for later use
    #if [ "$time" != "" ]; then
        #time=$($JSON_TOOL  "$DATA_MSG" "time")
        #re_do_action_log "=============== time: $time"
        # XQFunction.forkExec("echo 'ok,xiaoqiang' > /tmp/ntp.status; sleep 3; date -s \""..time.."\"")
        #echo 'ok,xiaoqiang' > /tmp/ntp.status
        #date -s "$time"
    #fi

    return
}

do_set_backhaul_mode()
{
    backhaul_mode=$($JSON_TOOL  "$DATA_MSG" "backhaul_mode")
    re_do_action_log "=============== backhaul_mode: $backhaul_mode"
    uci -q set repacd.WiFiLink.2GIndependentChannelSelectionEnable=$backhaul_mode
    uci commit repacd
    uci -q set xiaoqiang.common.son_no_24backhaul=$backhaul_mode
    uci commit xiaoqiang
    /etc/init.d/repacd restart
    re_do_action_log "=============== call repacd restart."
    return
}
## notify REs with precompose cmd, if re exist&active
# 1. get and validate WHC_RE active in tbus list, exclude repeater & xiaomi_plc
# 2. run tbus cmd



# msg format as follow
#local info = {
#    ["timezone"] = tzone,
#    ["index"] = index,
#}
#local msg = {
#    ["cmd"] = "sync_time",
#    ["msg"] = j_info,
#}

# {"cmd":"sync_time","index":"0","timezone":"CST+12"}
DATA_MSG="$1"
#main
re_do_action_log "get msg: $DATA_MSG"

#parse cmd
cmd=`$JSON_TOOL "$DATA_MSG" "cmd"`
#timezone=`$JSON_TOOL "$DATA_MSG" "timezone"`
re_do_action_log "=============== cmd: $cmd"
case $cmd in
    sync_time)
        re_do_action_log "=============== do cmd: sync_time"
        do_sync_time
        return $?
    ;;

    set_backhaul_mode)
        re_do_action_log "=============== do cmd: set_backhaul_mode"
        do_set_backhaul_mode
        return $?
    ;;
    test)
        re_do_action_log "=============== test "
        return $?
    ;;

    *)
        my_usage
        return 0
    ;;
esac


return $?

