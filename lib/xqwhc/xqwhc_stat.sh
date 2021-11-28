#!/bin/sh

# xqwhc_stat: check and supervise whc stat

. /lib/xqwhc/xqwhc_public.sh

## check self stat after dev init
# for cap, wifi up,
# for re, wifi up, wifi assoc done

# for cap, check ap iface
# for re, check ap & sta iface

ERR_ROLE=10
ERR_CHECK_WIFI_VAP=11
#ERR_CHECK_PLC=14
ERR_CHECK_ASSOC=15
ERR_NORUN_WSPLCD=16
ERR_NORUN_HYD=17
ERR_NORUN_REPACD_RUN=18
ERR_NORUN_OTHER=19

# check device is son mode, CAP or RE
xqwhc_is_cap()
{
    # repacd.role?
    local role=`uci -q get repacd.repacd.Role`
    [ "CAP" = "$role" ] || return $ERR_ROLE

    [ "`uci -q get xiaoqiang.common.NETMODE`" = "whc_cap" ] && return 0 || return $ERR_ROLE

    # server process active?
    pidof hyd >/dev/null 2>&1 || {
        return $ERR_NORUN_HYD
    }

    return 0
}

xqwhc_is_re()
{
    # repacd.role?
    local role=`uci -q get repacd.repacd.Role`
    [ "CAP" = "$role" ] && return $ERR_ROLE

    [ "`uci -q get xiaoqiang.common.NETMODE`" = "whc_re" ] && return 0 || return $ERR_ROLE

    # server process active?
    pidof repacd-run.sh >/dev/null 2>&1 || {
        return $ERR_NORUN_REPACD_RUN
    }

    pidof hyd >/dev/null 2>&1 || {
        return $ERR_NORUN_HYD
    }

    return 0
}


# return CAP RE 
xqwhc_get_stat()
{

    xqwhc_is_cap && {
        echo -n "CAP"
        return 0
    }


    xqwhc_is_re && {
        echo -n "RE"
        return 0
    }

    echo -n "router"
    return 0;
}


__check_wifi_vap()
{
    . /lib/xqwhc/network_lal.sh
    local list_all
    nlal_get_wifi_iface_bynet $NETWORK_PRIV list_all

    [ -z "$list_all" ] && {
        WHC_LOGE " failed to get wifi bh iface"
        return $ERR_CHECK_WIFI_VAP
    }

    # check vap up in iwconfig
    for ifn in $list_all; do
        nlal_check_wifi_iface_up "$ifn" "son" || {
            WHC_LOGE " failed to confirm wifi bh iface $ifn up"
            return $ERR_CHECK_WIFI_VAP
        }
    done

    return 0;
}

# only re
__check_wifi_assoc()
{
    

    return 0;   
}

__check_whc_service()
{
    # hyd run?
    pidof hyd >/dev/null 2>&1 || {
        WHC_LOGE " check, hyd not running!"
        return $ERR_NORUN_HYD
    }

    xqwhc_is_re && {
        pidof repacd-run.sh >/dev/null 2>&1 || {
            WHC_LOGE " check, repacd-run.sh not running on RE!"
            return $ERR_NORUN_REPACD_RUN
        }
    }

    WHC_LOGI " confirm whc service run properly "

    return 0
}

# abandon
xqwhc_check_cap_init()
{
    if ! __check_wifi_vap ; then
        message="\" error cap init, wifi vap check\""
        return $ERR_CHECK_WIFI_VAP
    fi

    return 0
}

# abandon
xqwhc_check_re_init()
{
    if ! __check_wifi_vap ; then
        message="\" error re init, wifi vap check\""
        return $ERR_CHECK_WIFI_VAP
    fi

    if !__check_wifi_assoc ; then
        message="\" error re init, wifi no assoc!\""
        return $ERR_CHECK_ASSOC
    fi

    return 0
}

# raw check init config activate done?
# 1. common: hyd run? wifi ap up
# 2. RE: wifi sta up? repacd-run.sh run?
xqwhc_rawcheck()
{
    __check_wifi_vap || return $? 

    ## WAR for bridge NO ifas issue of netifd, jira XP-20132
    # check bridge ifaces is exist?
    if false; then
      local list=`brctl show 2>/dev/null | awk 'NR==2 {print $4}'`
      list="$list `brctl show 2>/dev/null | awk 'NR>2 {print $1}' | xargs`"
      [ -z "$list" ] && {
          WHC_LOGI " ***exception, wifi up, but bridge NULL, reset network"
          /etc/init.d/network restart &
      }
    fi

    # skip whc service check to down timecost in init
    #__check_whc_service || return $?

    return 0;
}


