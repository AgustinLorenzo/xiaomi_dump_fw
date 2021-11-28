#!/bin/sh
# Copyright (C) 2018 Xiaomi

CHECK_INTERVAL_SECS=60

openvpn_log()
{
    logger -p debug -t openvpn "$1"
}

deamon_run()
{
    # stop first
    deamon_stop
    # start new
    openvpn_log "openvpn deamon start"
    counter=0;
    sleep 120
    while true
    do
        local openvpn_network=$(uci get network.openvpn)
        local auto=$(uci get network.openvpn.auto)
        #local openvpn_firewall=$(uci get firewall.openvpn)
        date_tag=$(date +%F" "%H:%M:%S)
        openvpn_log "openvpn check counter=$counter  time:$date_tag"
        #echo $openvpn_network
        #echo $auto
        [[ "$openvpn_network" == "interface" && "$auto" == "1" ]] && {
            local openvpn_stat=$(ps | grep openvpn.mi.pid | grep -v grep 2>/dev/null)
            local route_num=$(ip route |wc -l 2>/dev/null)
            #openvpn_log "openvpn restart counter=$counter  openvpn_stat:$openvpn_stat"
            [[ "$openvpn_stat" == "" || $route_num -lt 20 ]] && {
                counter++
                openvpn_log "openvpn restart route_num: $route_num counter=$counter  time:$date_tag"
                logger -p info -t openvpn "stat_points_none openvpn restart counter=$counter at time=$date_tag"
                # restart openvpn
                /etc/init.d/openvpn reload
            }
        }
        sleep $CHECK_INTERVAL_SECS
    done
}

deamon_stop()
{
    local this_pid=$$
    local one_pid=""
    local _pid_list=""
    echo $$ >/tmp/openvpn_deamon.pid

    _pid_list=$(ps w|grep openvpn_deamon.sh|grep -v grep |grep -v counting|awk '{print $1}')
    for one_pid in $_pid_list
    do
        openvpn_log "current try pid "$one_pid" end"
        [ "$one_pid" != "$this_pid" ] && {
            openvpn_log "openvpn_deamon kill "$one_pid
            kill -9 $one_pid
        }
    done
    openvpn_log "openvpn deamon stop"
}

case "$1" in
    "start")
        deamon_run
        ;;
    "stop")
        deamon_stop
        ;;
    *)
        echo "USAGE: $0 start | stop"
        exit 1;
        ;;
esac

exit 0;
