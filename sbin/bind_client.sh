#!/bin/sh
# Copyright (C) 2016 Xiaomi
#
#set -x

. /lib/functions.sh
. /usr/share/libubox/jshn.sh

LOCKFILE=/var/lock/re_bind.lock

bind_log()
{
    echo "$1"
    local date=$(date)
    logger -p warn "stat_points_none bind=$1 at $date"
}

# parse json code
parse_json()
{
    # {"code":0,"data":{"bind":1,"admin":499744955}}
    echo "$1" | awk -F "$2" '{print$2}'|awk -F "" '{print $3}'
}

# do on client, after get his signatures
check_my_bind_status()
{
    local bind_status=$(timeout -t 5 matool --method api_call --params "/device/minet_get_bindinfo" 2>/dev/null)
    if [ $? -ne 0 ];
    then
        echo "[matool --method minet_get_bindinfo] error!"
        return 2
    fi
    # {"code":0,"data":{"bind":1,"admin":499744955}}
    local code=$(parse_json $bind_status "code")
    if [ -n "$code" ] && [ $code -eq 0 ]; then
        #bind_log "code: $code"
        local bind=$(parse_json $bind_status "bind")
        bind_log "my bind_status: $bind"
        return $bind
    else
        return 0
    fi
}

bind_remote_client()
{
    local HardwareVersion=$1
    local SN=$2
    local ROM=$3
    local IP=$4
    local RECORD=$5
    local Channel=$6
    #local Channel=$(uci get /usr/share/xiaoqiang/xiaoqiang_version.version.CHANNEL)
    # 1. get signature for client
    #bind_log "HardwareVersion: $HardwareVersion"
    #bind_log "SN: $SN"
    #bind_log "ROM: $ROM"
    #bind_log "IP: $IP"
    #bind_log "client Channel: $Channel"
    # get signatures for client
    # matool --method sign --params "{SN}&{HardwareVersion}&{ROM}&{Channel}"
    #matool --method sign --params "{$SN}&{$HardwareVersion}&{$ROM}&{$Channel}"
    bind_log "matool --method sign --params \"$SN&$HardwareVersion&$ROM&$Channel\""
    local signature=$(timeout -t 5 matool --method sign --params "$SN&$HardwareVersion&$ROM&$Channel" 2>/dev/null)
    if [ $? -ne 0 ];
    then
        echo "[matool --method sign] error!"
        return 1
    fi
    #bind_log "get signature: $signature"

    # 2. sent my device ID and signature to client
    #tbus call 192.168.31.73 bind '{"action":1,"msg":"hello"}'
    #signature="582e7ad35a1479f9f3e2cb7f0855b5549b0e1501"
    #IP="192.168.31.73"
    local deviceID=$(uci get messaging.deviceInfo.DEVICE_ID 2>/dev/null)
    #bind_log "get deviceID: $deviceID"

    #bind_log "CMD: timeout -t 10 tbus call $IP bind  {\"record\":\"$RECORD\",\"deviceID\":\"$deviceID\",\"sign\":\"$signature\"}"
    #local ret=$(timeout -t 10 tbus call $IP bind {\"record\":\"$RECORD\",\"deviceID\":\"$deviceID\",\"sign\":\"$signature\"})
    #bind_log "client bind return: $ret"
    #if [ $? -ne 0 ];
    #then
    #    bind_log "[tbus call $IP bind] error!"
    #    return 1
    #fi
    #bind_log "timeout -t 5 tbus call $IP bind "\'{\"action\":1,\"deviceID\":\"$deviceID\",\"sign\":\"$signature\"}\'""

    jmsg="{\"record\":\"$RECORD\",\"deviceID\":\"$deviceID\",\"sign\":\"$signature\"}"
    json_add_string "method" "bind"
    json_add_string "payload" $jmsg
    json_str=`json_dump`
    echo $json_str
    ubus call xq_info_sync_mqtt send_msg "$json_str"
}

# do on client, after get his signatures
bind_me()
{
    #matool --method joint_bind --params {device_id} {sign}
    local device_id=$1
    local sign=$2
    local record=$3

    # check init flag first
    INIT_FLAG="$(uci get xiaoqiang.common.INITTED 2>/dev/null)"
    if [ "${INIT_FLAG}" != 'YES' ]; then
        bind_log "router not init, jump bind."
        return 0
    fi

    # check bind record
    bind_record="$(uci get bind.info.record 2>/dev/null)"
    if [ "${bind_record}" == "$record" ]; then
        bind_log "re already bind, jump bind"
        return 0
    fi

    # do join bind
    bind_log "get master deviceID: $device_id"
    bind_log "get master sign: $sign"
    bind_log "get master record: $record"
    bind_log "cmd: timeout -t 5 matool --method joint_bind --params "$device_id" "$sign" 2>/dev/null"
    timeout -t 5 matool --method joint_bind --params "$device_id" "$sign" 2>/dev/null
    if [ $? -ne 0 ]; then
        bind_log "[method joint_bind] error!"
        return 0
    else
        # update bind record according to master bind info.
        uci set bind.info.status=1
        uci set bind.info.record=$record
        uci set bind.info.remoteID=$device_id
        uci commit bind
        bind_log "[method joint_bind] ok!"

        # push xqwhc setkv on bind success
        logger -p 1 -t "xqwhc_push" " RE push xqwhc kv info on bind success"
        sh /usr/sbin/xqwhc_push.cron now &
    fi

    local deviceID=$(uci get messaging.deviceInfo.DEVICE_ID 2>/dev/null)
    bind_log "get new deviceID: $deviceID"
    # check new status
    check_my_bind_status
}


OPT=$1
#bind_log "OPT: $OPT"

json_init

echo  $OPT
case $OPT in
    bind_remote)
        #1. check bind status
        check_my_bind_status
        if [ $? -eq 1 ]; then
            bind_remote_client "$2" "$3" "$4" "$5" "$6" "$7"
        fi
        return 0
        ;;
    bind_me)
	trap "lock -u ${LOCKFILE}; exit" EXIT HUP INT QUIT PIPE TERM
	if ! lock -n $LOCKFILE; then
    	    dlog "re bind already running, skip this process"
    	    trap '' EXIT
    	    exit 0
	fi

        #check_my_bind_status
        # just do when not binded
        #if [ $? -eq 0 ]; then
        #    bind_me "$2" "$3" "$4"
        #fi
        # bind all the time
        bind_me "$2" "$3" "$4"
                
        return 0
        ;;
    *)
        return 0
        ;;
esac
