#!/bin/sh

# miwifi xqled api
# provide
#  uci parse
#  led func parse
#  unify control

. /lib/functions.sh
. /lib/xqled/xqled_hal.sh


THIS_MODULE="xqled"
STYPE_LED="led"
STYPE_FUNC="func"
TRIGGER_BLINK="blink"
TRIGGER_ON="on"
TRIGGER_OFF="off"


USE_BLUE_SWT=1
[ $USE_BLUE_SWT -gt 0 ] && BLUE_SWT=`uci -q get xiaoqiang.common.BLUE_LED`


# log
XQLED_DBG=1

XQTAG="xqled"
XQLED_LOGI()
{
    [ "$XQLED_DBG" -gt 1 ] && sout="-s"
    logger "$sout" -p 2 -t "$XQTAG" "$1"
}

XQLED_LOGE()
{
    [ "$XQLED_DBG" -gt 1 ] && sout="-s"
    logger "$sout" -p 1 -t "$XQTAG" "$1"
}

XQLED_LOGD()
{
    [ "$XQLED_DBG" -gt 1 ] && {
        sout="-s"
        logger "$sout" -p 2 -t "$XQTAG" "$1"
    }
}



MS2UNIT()
{
    local val=$(($1 / 100))
    [ -z "$val" ] && val=1
    echo -n "$val"
}



config_load "$THIS_MODULE"

# get the all te support func sect-name
__slist_get()
{
    local stype="$1"
    local list=""

__func_get()
{ append list "$1"; }

    config_foreach __func_get $stype
    echo -n "$list"
}


xqled_led_list=$(__slist_get "$STYPE_LED")
xqled_func_list=$(__slist_get "$STYPE_FUNC")


__validate_func()
{
    local func="$1"

    # check func is support in the list
    list_contains xqled_func_list "$func" || {
        XQLED_LOGE " xqled func [$func] NOT defined!"
        return 11
    }

    return 0
}

__validate_led()
{
    local led="$1"

    # check func is support in the list
    list_contains xqled_led_list "$led" || {
        XQLED_LOGE " xqled name [$led] NOT defined!"
        return 12
    }

    return 0
}

__validate_color()
{
    local led=$1
    local clr=$2

    gg=$(config_get "$led" "$clr")
    [ -n "$gg" ] || {
        XQLED_LOGE " xqled [$led] NOT define color[$clr]"
        return 13
    }
}


# xqled predefined func active
# input: led func name predef in uci
# key ele: ledname, color, blink 
xqled_func_act()
{
    local func="$1"

    __validate_func "$func" || return $?

    local nled=$(config_get $func nled)
    __validate_led "$nled" || return $?

    local color=$(config_get $func color)
    __validate_color "$nled" "$color" || return $?

    local trg=$(config_get $func trigger)

    [ -z "$nled" -o -z "$color" -o -z "$trg" ] && {
        XQLED_LOGE " xqled [$func] option inv, $nled, $color, $trg"
        return 22
    }

    # check blue led switch
    if [ "$USE_BLUE_SWT" -gt 0 ]; then
        [ "$color" = "blue" -a "$BLUE_SWT" = "0" -a "$trg" != "$TRIGGER_OFF" ] && {
            XQLED_LOGI "  xqled ignore func [$func] for xiaoqiang.common.BLUE_LED "
            trg="$TRIGGER_OFF"
        }
    fi

    # reset all gpio of led
    local black_gpios="$(config_get $nled black)"
    for gg in $black_gpios; do
        xqled_hal_ctr "$gg" $LED_OFF
    done

    # get gpio by led + color
    local gpios="$(config_get $nled $color)"

  for gg in $gpios; do
    if [ "$trg" = "$TRIGGER_BLINK" ]; then
        # blink
        config_get mson $func msec_on 800
        config_get msoff $func msec_off 800

        xqled_hal_ctr "$gg" $LED_BLINK $(MS2UNIT $mson) $(MS2UNIT $msoff)
    elif [ "$trg" = "$TRIGGER_ON" ]; then
        # led on
        xqled_hal_ctr "$gg" $LED_ON
    else
        # led off
        :
    fi
  done

    return $?

}

