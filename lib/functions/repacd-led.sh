#!/bin/sh
# Copyright (c) 2015 Qualcomm Atheros, Inc.
#
# All Rights Reserved.
# Qualcomm Atheros Confidential and Proprietary.

. /lib/functions.sh
LED_DEBUG_OUTOUT=0

__repacd_led_info() {
    local stderr=''
    if [ "$LED_DEBUG_OUTOUT" -gt 0 ]; then
        stderr='-s'
    fi  

    logger $stderr -t repacd.led -p user.info "$1"
}



# Determine the SysFS path corresponding to the LED with the given name.
# input: $1 - name: the virtual name of the LED (used within the UCI system
#                   configuration)
# output: $2 - sysfs path: the parameter into which to store the sysfs path
# return: 0 on success; 1 if the LED could not be located by name
__repacd_led_get_path() {
    local led_name=$1 sysfs_name
    config_load system
    config_get sysfs_name "$led_name" 'sysfs' ''
    if [ -n "$sysfs_name" ]; then
        eval "$2=/sys/class/leds/$sysfs_name"
        return 0
    else  # not found
        return 1
    fi
}

__repacd_led_set_state_qca() {
    local state_name=$1 index=$2
    local name trigger brightness delay_on delay_off
    local sysfs_path

    config_load repacd
    config_get name "$state_name" "Name_${index}" ''
    if [ -n "$name" ]; then
        config_get trigger "$state_name" "Trigger_${index}" ''
        config_get brightness "$state_name" "Brightness_${index}" ''
        if [ "$trigger" = 'timer' ]; then
            config_get delay_on "$state_name" "DelayOn_${index}" ''
            config_get delay_off "$state_name" "DelayOff_${index}" ''
        fi

        __repacd_led_get_path "$name" sysfs_path

        # Now activate the changes if all of the values are valid.
        if [ -n "$trigger" ] && [ -n "$brightness" ] && [ -n "$sysfs_path" ]; then
            # Change the mode first so that any additional values can be set.
            echo "$trigger" > "$sysfs_path/trigger"
            echo "$brightness" > "$sysfs_path/brightness"

            # The on/off values only get written for timer mode (as the sysfs
            # files do not even exist in other modes).
            #
            # Note that a different value is first written to force the blink
            # rate to be updated. Without this, it seems that the LEDs do not
            # blink if the default values (of 500 ms on/off) are written.
            if [ "$trigger" = 'timer' ] && [ -n "$delay_on" ]; then
                echo 1 > "$sysfs_path/delay_on"
                echo "$delay_on" > "$sysfs_path/delay_on"
            fi

            if [ "$trigger" = 'timer' ] && [ -n "$delay_off" ]; then
                echo 1 > "$sysfs_path/delay_off"
                echo "$delay_off" > "$sysfs_path/delay_off"
            fi
        fi
    fi
}

## represent repacd state by led beheave
# input $1: state name defined in repacd.uci
__repacd_led_set_state()
{
    local state_name="$1"
    local index=$2

    # led name defined in system.uci, with rgb val, with rgb value
    config_load repacd
    config_get name "$state_name" "Name_${index}" ''
    config_get brightness "$state_name" "Brightness_${index}" '0'

    if [ -z "$name" -o "$brightness" = '0' ]; then
       return 0;
    fi

    local color="`echo -n $name | sed 's/led_//'`"

    config_get trigger "$state_name" "Trigger_${index}" ''

    __repacd_led_info " @@@@@ set state $state_name, $name, $trigger"
    
    if [ "$trigger" = 'timer' ]; then
        config_get delay_on "$state_name" "DelayOn_${index}" ''
        config_get delay_off "$state_name" "DelayOff_${index}" ''

        gpio_led l $color $delay_on $delay_off &
    else
        gpio_led $color on &
    fi
}

# Update the LEDs to the state indicated based on the configuration file.
# input: $1 - state name: the name to use as the section name when looking
#                         up the LED configuration
repacd_led_set_states() {
    # For now, we only support up to 2 LEDs
    for index in $(seq 1 2)
    do
        __repacd_led_set_state "$1" "$index"
    done
}
