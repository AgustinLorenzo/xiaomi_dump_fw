#!/bin/sh
# Copyright (C) 2015 Xiaomi

wanip_status="/tmp/router_in_xiaomi"
interval=5

security_check_log()
{
    logger -p debug -t wifi_security_check "$1"
}

# check guest wifi config status
# return 0: close
# return 1: open
get_guestwifi_status()
{
    # get guestwifi config
    guest_config="$(uci show |grep wifishare  2>/dev/NULL)"
    if [ "$guest_config" != "" ]
    then
        return 1;
    else
        return 0;
    fi
}

# if router in xiaomi office, shutdown guest wifi.
guestwifi_shutdown()
{
    guest_name="$(uci get misc.wireless.guest_2G 2>/dev/NULL)"
    #lan_ip="$(uci get network.lan.ipaddr 2>/dev/NULL)"
    guestwifi_up="$(ifconfig $guest_name |grep RUNNING  2>/dev/NULL)"
    route_in_xiaomi="$(cat  $wanip_status)"

    #security_check_log $guest_name
    #security_check_log $route_in_xiaomi
    #security_check_log $guestwifi_up

    date_tag=$(date +%F" "%H:%M:%S)

    # get guestwifi config status
    #get_guestwifi_status
    #guest_config_open=$?
    #security_check_log "guest_config_open is $guest_config_open"
    disabled="$(uci get wireless.guest_2G.disabled 2>/dev/null)"

    # if router in xiaomi, shutdown
    if [ $route_in_xiaomi == 0 ]; then
        if [ $disabled == "0" ]; then
            # if not in xiaomi, but not running, ifconfig up it.
            if [ "$guestwifi_up" == "" ]; then
                #echo "guest wifi is down and not in xiaomi, ifconfig up it."
                ifconfig $guest_name up
		hostapd_cli -i $guest_name -p /var/run/hostapd-wifi1 enable
                logger -p info -t wifishare "stat_points_none guest wifi is down but not in xiaomi, open it. $date_tag"
                security_check_log "guest wifi is down and not in xiaomi, ifconfig up it."
            fi
        fi
    else
        # other condition: if guest [share] wifi is running, shutdown it !!!!
        encryption="$(uci get wireless.guest_2G.encryption 2>/dev/NULL)" 
        if [ "$encryption" == "none" ] && [ "$guestwifi_up" != "" ]; then
            #echo "guest wifi is up in xiamo, shutdown it."
		ifconfig $guest_name down
		hostapd_cli -i $guest_name -p /var/run/hostapd-wifi1 disable
            security_check_log "guest wifi is up in xiamo, shutdown it."
            logger -p info -t wifishare "stat_points_none wifishare_wanip=guest wifi is up in xiaomi, shutdown it. $date_tag"
        fi
    fi
}

# security check logic
security_check_start()
{
    # kill old deamon first, if exist.
    security_check_stop
    echo 0 > /tmp/smart_force_wifi_down
    while true
    do
        # if smartcontroller force wifi down, jump check
        force_down="$(cat /tmp/smart_force_wifi_down)"
        if [ $force_down == 1 ]; then
            sleep $interval
            continue
        fi
        # check router whether in xiaomi office, for guest wifi.
        guestwifi_shutdown

        # other check
        sleep $interval
    done
}

# kill all start deamon
security_check_stop()
{
    date_tag=$(date +%F" "%H:%M:%S)
    this_pid=$$
    one_pid=""
    _pid_list=""
    echo $$ >/tmp/security_check.pid

    _pid_list=$(ps w|grep security_check.sh|grep -v grep |grep -v counting|awk '{print $1}')
    for one_pid in $_pid_list
    do
        echo "get security check pid "$one_pid" end"
        [ "$one_pid" != "$this_pid" ] && {
            echo "security check kill "$one_pid
            kill -9 $one_pid
        }
    done

    guest_name="$(uci get misc.wireless.guest_2G 2>/dev/NULL)"
    guestwifi_up="$(ifconfig $guest_name |grep RUNNING  2>/dev/NULL)"
    guest_config="$(uci show |grep wifishare  2>/dev/NULL)"
    encryption="$(uci get wireless.guest_2G.encryption 2>/dev/NULL)"
    _passwd="$(uci get wireless.guest_2G.key 2>/dev/null)"
    disabled="$(uci get wireless.guest_2G.disabled 2>/dev/null)"

    # make guest [share] wifi down, when guest wifi off. for R4 ...
    #if [ "$encryption" == "none" ] && [ "$_passwd" != "12345678" ] && [ "$guestwifi_up" != "" ] && [ "$guest_config" == "" ]; then
    if [ "$disabled" == "1" ] && [ "$guestwifi_up" != "" ]; then
        ifconfig $guest_name down
        security_check_log "security check stop, shutdown guest wifi."
        logger -p info -t wifishare "stat_points_none wifishare_wanip= wifi security check stop, shutdown it. $date_tag"
    fi
    security_check_log "security check daemon stop"
}

OPT=$1

security_check_log "$OPT"

case $OPT in
    on)
        security_check_start
        return $?
    ;;

    off)
        security_check_stop
        return $?
    ;;
esac

