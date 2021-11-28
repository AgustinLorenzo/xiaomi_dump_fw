#!/bin/sh
# led controller module hardware abstract layer
# this file should modified depends on led driver

export INC_LED_PUB="INC"

LED_ON=0
LED_OFF=1
LED_BLINK=2


# log trace
LOGF="/tmp/log/xqled.log"
__TRACE()
{
    local time=`date +%Y%m%d-%H.%M.%S`
	if false; then
    [ `stat -c%s "$LOGF"` -gt 50000 ] && {
        echo -e "${time}    new log file" > $LOGF
    }   
	fi

    local item="${time}  $1"
    [ -d "/tmp/log" ] || mkdir -p "/tmp/log"
    echo -e "$item" >> $LOGF
}

# key arg, gpio, on/off, blink
__hal_led_on()
{
    gpio $1 0
}

__hal_led_off()
{
    gpio $1 1
}

__hal_led_blink()
{
    gpio l $2 $1
}

# led gpio controll
# xqled_hal_ctr 6 0   -- gpio 6 on
# xqled_hal_ctr 6 1   -- gpio 6 off
# xqled_hal_ctr 6 2 8 8 -- gpio 6 blink,on 800ms off 800ms
xqled_hal_ctr()
{
    local gpio="$1"
    local swt="$2"

    if [ "$swt" -eq "$LED_ON" ]; then
        __hal_led_on $1
    elif [ "$swt" -eq "$LED_OFF" ]; then
        __hal_led_off $1
    elif [ "$swt" -eq "$LED_BLINK" ]; then
        __hal_led_blink $1 $3 $4
    fi

    return $?
}

# ONLY called on ramfs without uci support, to control led  SYS
# input, color. trigger, blinkon, blinkoff
# xqled_hal_ctr_inramfs red 2 3 3   -- red blink 300ms
# xqled_hal_ctr_inramfs yellow 0    -- yellow on
# xqled_hal_ctr_inramfs blue 1      -- blue off
xqled_hal_ctr_inramfs()
{
    # define gpio pin of color, vary in platform
    local gpio_yellow="2"
    local gpio_blue="3"
    local gpio_purple="2 3"
    local gpio_red="2 3"
    local gpio_all="2 3"

    local color="$1"
    local swt="$2"
    eval pins='$'gpio_$color
    [ -z "$pins" ] && {
        echo "  xqled in ramfs, color[$color] NO gpio pin defined! "
        exit 1
    }

    # reset led
    for pp in $gpio_all; do
        __hal_led_off $pp
    done

    for pp in $pins; do
        if [ "$swt" -eq "$LED_ON" ]; then
            __hal_led_on $pp
        elif [ "$swt" -eq "$LED_OFF" ]; then
            __hal_led_off $pp
        elif [ "$swt" -eq "$LED_BLINK" ]; then
            __hal_led_blink $pp $3 $4
        fi
    done

}


