#!/bin/sh
# Copyright (c) 2015-2017 Qualcomm Technologies, Inc.
#
# All Rights Reserved.
# Confidential and Proprietary - Qualcomm Technologies, Inc.
#
# 2015-2016 Qualcomm Atheros, Inc.
#
# All Rights Reserved.
# Qualcomm Atheros Confidential and Proprietary.

WIFIMON_DEBUG_OUTOUT=0

# Set this to a filename to log all commands executed.
# The output of relevant commands will be appended to the file.
WIFIMON_DEBUG_COMMAND_FILE=

## miwifi: add new state to skip wlan bh check if eth bh find
WIFIMON_STATE_IGN_BH='IGN_WLAN_BH'
WIFIMON_STATE_NOT_ASSOCIATED='NotAssociated'
WIFIMON_STATE_AUTOCONFIG_IN_PROGRESS='AutoConfigInProgress'
WIFIMON_STATE_MEASURING='Measuring'
WIFIMON_STATE_WPS_TIMEOUT='WPSTimeout'
WIFIMON_STATE_BSSID_ASSOC_TIMEOUT='BSSIDAssocTimeout'
WIFIMON_STATE_ASSOC_TIMEOUT='AssocTimeout'
WIFIMON_STATE_RE_MOVE_CLOSER='RE_MoveCloser'
WIFIMON_STATE_RE_MOVE_FARTHER='RE_MoveFarther'
WIFIMON_STATE_RE_LOCATION_SUITABLE='RE_LocationSuitable'
WIFIMON_STATE_CL_LINK_SUFFICIENT='CL_LinkSufficient'
WIFIMON_STATE_CL_LINK_INADEQUATE='CL_LinkInadequate'
WIFIMON_STATE_CL_ACTING_AS_RE='CL_ActingAsRE'

WIFIMON_PIPE_NAME='/var/run/repacd.pipe'

RE_ROOT_AP_DISTANCE_INVALID='255'
RE_ZERO_BSSID="00:00:00:00:00:00"

config_load 'repacd'
config_get_bool wifimon_wxt repacd 'ForceWextMode' '0'

wifimon_cfg=
config_load 'qcacfg80211'
config_get wifimon_cfg 'config' 'enable' '1'

if [ "$wifimon_wxt" == "0" -a "$wifimon_cfg" == "1" ]; then
    REPACD_CFG80211=-cfg80211
else
    REPACD_CFG80211=
fi

. /lib/functions.sh
. /lib/functions/whc-network.sh
. /lib/xqwhc/xqwhc.sh

# State information
sta_iface_24g= sta_iface_24g_config_name=
sta_iface_5g= sta_iface_5g_config_name= unknown_ifaces=0
measurement_sta_iface= measurement_sta_iface_config_name=
assoc_timeout_logged=0 wps_timeout_logged=0
wps_in_progress=0 wps_start_time=''
wps_stabilization=0 wps_assoc_count=0
auto_mode_stabilization=0 auto_mode_assoc_count=0
bssid_stabilization=0 bssid_assoc_count=0 bssid_resolve_complete=0
assoc_start_time='' last_assoc_state=0 backhaul_eval_time='' force_down_5g_timestamp=''
ping_running=0 last_ping_gw_ip=
ping_running_pid=''
rssi_num=0 rssi_filename=
force_down_5g=0 down_time_2g='' measurement_eval_count=0
force_down_24g=0 badlink_start_time_5g='' badlink_switch_inprogress=0
rate_num=0 rate_min=0 rate_max=0 rate_pref2G=0 rate_to_CAP_filename=''
rssi_counter=0
is_24G_down_by_independent_channel=0
rssi_idle_time=0
new_bestap='' new_bestap_otherband='' bestap_filename=''
bssid_resolve_state= nolink_detected_5g=0
curr_root_distance=$RE_ROOT_AP_DISTANCE_INVALID
ignore_24g_assoc=0
my_uplink_rate_filename=
MoveFromCAP_snr_threshold= CAP_snr_filename=
wifi_2G_interface_name=
rate_to_CAP=0

# Config parameters
device_type= config_re_mode= default_re_mode=
min_wps_assoc= min_auto_mode_assoc= min_bssid_assoc=
rssi_samples= rssi_far= rssi_near= rssi_min= rssi_pref2G= snr_pref2G=
assoc_timeout= wps_timeout= config_downtime2G= measuring_attempts=0
rate_samples= percent_rate_min5G= percent_rate_max5G= percent_rate_pref2G=
daisy_chain= bssid_assoc_timeout= badlink_timeout5G=
config_short_eval_time5g=0 config_long_eval_time5g=0 config_eval_time24g=0
traffic_separation_enabled=0 traffic_separation_active=0
guest_backhaul= network_guest=
guest_preflink_down_start_time=0 guest_preflink_down_timeout=15
guest_preflink_up_start_time=0 guest_preflink_up_timeout=5
guest_link_override=0 guest_vid=102
is_independent_channel=_selection_enable=
quality_5g_rssi_level=
rssi_check_total_counter=
CAP_snr_threshold= MoveFromCAP_snr_hysteresis=
backhaul_mode_single=SINGLE


# Emit a message at debug level.
# input: $1 - the message to log
__repacd_wifimon_debug() {
    local stderr=''
    if [ "$WIFIMON_DEBUG_OUTOUT" -gt 0 ]; then
        stderr='-s'
    fi

    logger $stderr -t repacd.wifimon -p user.debug "$1"
}

__repacd_wifimon_info() {
    local stderr=''
    if [ "$WIFIMON_DEBUG_OUTOUT" -gt 0 ]; then
        stderr='-s'
    fi

    logger $stderr -t repacd.wifimon -p user.info "$1"
}

__repacd_wifimon_warn() {
    local stderr=''
    if [ "$WIFIMON_DEBUG_OUTOUT" -gt 0 ]; then
        stderr='-s'
    fi

    logger $stderr -t repacd.wifimon -p user.warn "$1"
}

# Log the output of a command to a file (when enabled).
# Log the output of a command to a file (when enabled).
# Log the output of a command to a file (when enabled).
# This is a nop unless WIFIMON_DEBUG_COMMAND_FILE is set.
# input: $1 - command output to log
__repacd_wifimon_dump_cmd() {
    if [ -n "$WIFIMON_DEBUG_COMMAND_FILE" ]; then
        touch $WIFIMON_DEBUG_COMMAND_FILE
        date >> $WIFIMON_DEBUG_COMMAND_FILE
        echo "$1" >> $WIFIMON_DEBUG_COMMAND_FILE
        echo >> $WIFIMON_DEBUG_COMMAND_FILE
    fi
}

# Emit a message at info level.
__repacd_wifimon_info() {
    local stderr=''
    if [ "$WIFIMON_DEBUG_OUTOUT" -gt 0 ]; then
        stderr='-s'
    fi

    logger $stderr -t repacd.wifimon -p user.info "$1"
}

# Obtain a timestamp from the system.
#
# These timestamps will be monontonically increasing and be unaffected by
# any time skew (eg. via NTP or manual date commands).
#
# output: $1 - the timestamp as an integer (with any fractional time truncated)
__repacd_wifimon_get_timestamp() {
    timestamp=`cat /proc/uptime | cut -d' ' -f1 | cut -d. -f 1`
    eval "$1=$timestamp"
}

# Terminate any background ping that may be running.
# If no background pings are running, this will be a nop.
__repacd_stop_ping() {
    if [ "$ping_running" -gt 0 ]; then
        #kill $ping_running_pid
        ## miwifi: fixup jobs list cumulate, for jobs -p always get former pids and insert new to the head
        ## list=`echo "$list" | awk 'NR==1 {print $1}'`
        local patstr="ping.*\..*\..*\..*-q -w 39 -c 37" # patstr must be same with repacd_start_ping cmdline 
        local list=`ps -w | grep "$patstr" | grep -v grep | awk '{print $1}' | xargs`
        #__repacd_wifimon_debug " @@ kill ping jobs $list"
        kill -9 $list 2>/dev/null
        ping_running=0
        __repacd_wifimon_debug "Stopped ping to GW IP $last_ping_gw_ip"
    fi

    if [ -n "$rssi_filename" ]; then
        # Clean up the temporary file
        rm -f $rssi_filename
        rssi_filename=
    fi
    if [ -n "$uplink_snr_filename" ]; then
        # Clean up the temporary file
        rm -f $uplink_snr_filename
        uplink_snr_filename=
    fi
    if [ -n "$rate_to_CAP_filename" ]; then
        # Clean up the temporary file
        rm -f $rate_to_CAP_filename
        rate_to_CAP_filename=
    fi
    if [ -n "$my_uplink_rate_filename" ]; then
        # Clean up the temporary file
        rm -f $my_uplink_rate_filename
        my_uplink_rate_filename=
    fi
    if [ -n "$bestap_filename" ]; then
        # Clean up the temporary file
        rm -f $bestap_filename
        bestap_filename=
    fi
    if [ -n "$CAP_snr_filename" ]; then
        # Clean up the temporary file
        rm -f $CAP_snr_filename
        CAP_snr_filename=
    fi

    # miwifi: delete all repacd-* tmp file
    rm -f /tmp/repacd-rssi.* /tmp/repacd-rate-toCAP.* /tmp/repacd-CAP-snr.* /tmp/repacd-bestap.* /tmp/repacd-rate-myUplink.*
}

# Start a background ping to the gateway address (if it can be resolved).
# This helps ensure the RSSI values are updated (as firmware will not report
# updates if only beacons are being received on the STA interface).
# input: $1 - network: the name of the network being managed
# return: 0 if the ping was started or is already running; otherwise 1
__repacd_start_ping() {
    gw_ip=`route -n | grep ^0.0.0.0 | grep br-$1 | awk '{print $2}'`
    if [ -n "$gw_ip" ]; then
        if [ ! "$gw_ip" = "$last_ping_gw_ip" ]; then
            # First need to kill the existing one due to the IP change.
            __repacd_stop_ping
            # This will leave ping_running set to 0.
        fi

        if [ "$ping_running" -eq 0 ]; then
            __repacd_wifimon_debug "Pinging GW IP $gw_ip"

            # Unfortunately the busybox ping command does not support an
            # interval. Thus, we can only ping once per second so there will
            # only be a handful of measurements over the course of our RSSI
            # sampling.
            #ping $gw_ip > /dev/null & ping_running_pid=$!
            #__repacd_wifimon_debug "PID of running ping job=$ping_running_pid"
            ## miwifi: fixup jobs list cumulate, for jobs -p always get former pids and insert new to the head
            ping $gw_ip -q -w 39 -c 37 >/dev/null 2>&1 &
            ping_running=1
            last_ping_gw_ip=$gw_ip
        fi

        # Ping is running now or was started.
        return 0
    fi

    __repacd_wifimon_info "Failed to resolve GW when starting ping; will re-attempt"
    return 1
}

# Determine if the gateway is reachable.
#
# Ideally this would be limited to only the 5 GHz STA interface, but there
# is no good way to do this (since packets would need to be received on the
# bridge interface).
#
# return: 0 if the gateway is reachable; otherwise 1
__repacd_is_gw_reachable() {
    if [ -n "$last_ping_gw_ip" ]; then
        if ping -c 1 -W 1 ${last_ping_gw_ip} > /dev/null; then
            return 0
        fi
    fi

    # Gateway is unknown or is not reachable
    return 1
}

# Determine if the STA interface named is current associated and active.
#
# input: $1 - sta_iface: the name of the interface (eg. ath01)
# return: 0 if associated; 1 if not associated or empty interface name
__repacd_wifimon_is_active_assoc() {
    local sta_iface=$1
    if [ -n "$sta_iface" ]; then
#        local assoc_str=$(iwconfig $sta_iface | grep "Rate:" | awk '{print $2}' | cut -d: -f 2 | awk '{print $1}')
        local assoc_str=$(repacdcli $sta_iface get_bitrate)
        __repacd_wifimon_dump_cmd "Rate of $sta_iface: $assoc_str MB"

        if [ "$assoc_str" != 0 ]; then
            return 0
        else
            return 1
        fi
    else
        # An unknown STA interface is considered not associated.
        return 1
    fi
}

# Determine if the STA interface named is current associated.
#
# Note that for the purposes of this function, an empty interface name is
# considered associated. This is done because in some configurations, only
# one interface is enabled.
#
# input: $1 - sta_iface: the name of the interface (eg. ath01)
# return: 0 if associated or if the interface name is empty; otherwise 1
__repacd_wifimon_is_assoc() {
    local sta_iface=$1
    if [ -n "$sta_iface" ];
    then
        if [ "$sta_iface" = "$sta_iface_5g" ] &&
               [ "$force_down_5g" -gt 0 ];then
            return 0
        elif [ "$sta_iface" = "$sta_iface_24g" ] \
            && [ "$force_down_24g" -gt 0 ]; then
            return 0
        elif [ "$sta_iface" = "$sta_iface_24g" ] \
            && [ "$is_24G_down_by_independent_channel" -gt 0 ]; then
            return 0
        fi

        if __repacd_wifimon_is_active_assoc $sta_iface; then
            return 0
        else
            return 1
        fi
    else
        # An unknown STA interface is considered associated.
        return 0
    fi
}

# Determine if the device is already operating in the desired range extender
# mode when using automatic mode switching.
#
# input: $1 - cur_re_mode: the current operating range extender mode
# input: $2 - cur_re_submode: the current operating range extender sub-mode
# output: $3 - new_re_mode: the new range extender mode
# output: $4 - new_re_submode: the new range extender sub-mode
# return: 0 if already operating in the desired mode & submode; otherwise 1
__repacd_wifimon_resolve_mode() {
    local old_re_mode=$1
    local old_re_submode=$2
    local re_mode_changed=0

    # Finally, if the serving AP is operating in one of the special
    # modes, write back the association derived RE mode. Otherwise,
    # write back the default mode.
    if [ "$config_re_mode" = 'auto' ]; then
        # Since when operating in SON mode we rely on wsplcd/daisy to force
        # the association to the CAP, do not check whether the CAP is
        # the serving AP when determining whether to switch modes.
        if __repacd_wifimon_is_serving_ap_son; then
            if [ ! "$old_re_mode" = 'son' ]; then
                __repacd_wifimon_info "Serving AP has SON enabled"
                eval "$3=son"
                re_mode_changed=1
            fi
        elif __repacd_wifimon_is_serving_ap_wds; then
            if [ ! "$old_re_mode" = 'wds' ]; then
                __repacd_wifimon_info "Serving AP has WDS enabled"
                eval "$3=wds"
                re_mode_changed=1
            fi
        else
            if [ ! "$old_re_mode" = "$default_re_mode" ]; then
                __repacd_wifimon_info "Serving AP does not advertise WDS"
                eval "$3=$default_re_mode"
                re_mode_changed=1
            fi
        fi
    fi

    # By definition, when operating in non-auto mode, we are always in
    # the desired mode. But if there is any special sub-modes, handle it here.
    if __repacd_wifimon_is_serving_ap_son; then
        __repacd_wifimon_get_son_submode submode
        if [ ! "$old_re_submode" = "$submode" ]; then
            eval "$4=$submode"
        fi
    fi

    if [ "$re_mode_changed" -gt 0 ]; then
        return 1
    else
        return 0
    fi
}

# Determine if the peer BSSID has been written back to UCI.
# This assumes the wireless config file has already been loaded.
# input: $1 - iface_section: the name of the section in UCI
# return: 0 if the BSSID has been set or there is no section; otherwise 1
__repacd_wifimon_is_peer_bssid_set() {
    local iface_section=$1

    if [ -z "$iface_section" ]; then
        # Nothing to clone.
        return 0
    elif [ -n "$iface_section" ]; then
        config_get peer_bssid $iface_section 'bssid' ''
        #Change peer to resolved iff BSSID non-zero.
        if [ -n "$peer_bssid" -a "$peer_bssid" != "00:00:00:00:00:00" ]; then
            return 0
        fi
    fi

    return 1
}

# Determine if the peer BSSID has been written invalid forecully.
# This assumes the wireless config file has invalid bssid preconfigured.
# input: $1 - iface_section: the name of the section in UCI
# return: 0 if the BSSID has set to invalid; otherwise 1
__repacd_wifimon_is_peer_bssid_invalid() {
    local iface_section=$1

    config_get peer_bssid $iface_section 'bssid' ''
    #Check peer to resolved if BSSID non-zero.
    if [ -n "$peer_bssid" -a "$peer_bssid" = "00:00:00:00:00:00" ]; then
        return 0
    fi

    return 1
}

# Determine if the deep cloning process has completed (if enabled).
# return: 0 if the process is complete or is not enabled; otherwise 1
__repacd_wifimon_is_deep_cloning_complete() {
    # First check if wsplcd and deep cloning are even enabled. If not,
    # then consider it complete.
    local wsplcd_enabled
    local deep_cloning_enabled
    local config_sta_enabled
    local peer_bssid

    config_load wsplcd
    config_get wsplcd_enabled 'config' 'HyFiSecurity' '0'
    config_get deep_cloning_enabled 'config' 'DeepClone' '0'
    config_get config_sta_enabled 'config' 'ConfigSta' '0'

    if [ "$wsplcd_enabled" -eq 0 -o "$deep_cloning_enabled" -eq 0 -o \
         "$config_sta_enabled" -eq 0 ]; then
        return 0
    fi

    # For each of the STA interfaces, see if the peer BSSID has been set.
    config_load wireless
    __repacd_wifimon_is_peer_bssid_set $sta_iface_24g_config_name || return 1
    __repacd_wifimon_is_peer_bssid_set $sta_iface_5g_config_name || return 1

    return 0
}

# Determine if the STA association is stable enough to be able to start
# the next step of the process.
# return: 0 if the association is stable; non-zero if it is not yet deemed
#         stable
__repacd_wifimon_is_assoc_stable() {
    if [ "$wps_stabilization" -gt 0 ]; then
        if [ "$wps_assoc_count" -ge "$min_wps_assoc" ]; then
            return 0
        else
            return 1
        fi
    elif [ "$bssid_stabilization" -gt 0 ]; then
        if [ "$bssid_assoc_count" -ge "$min_bssid_assoc" ]; then
            return 0
        else
            return 1
        fi
    elif [ "$auto_mode_stabilization" -gt 0 ]; then
        if [ "$auto_mode_assoc_count" -ge "$min_auto_mode_assoc" ]; then
            return 0
        else
            return 1
        fi
    else
        # No stabilization in progress
        return 0
    fi
}

# Determine if the guest network's backhaul interface should be changed
# from prefered interface to non-prefered interface based on link status.
# If change has already made then monitor prefered interface, if prefered
# interface link looks good then change back to prefered interface.
# input: $1 - pref_iface: prefered sta interface
# input: $2 - other_iface: other non prefered interface
__repacd_wifimon_override_guest_backhaul() {
    local pref_iface=$1
    local other_iface=$2
    local force_pref_down=0
    local force_other_down=0
    local ifname

    if [ "$pref_iface" = "$sta_iface_5g" ]; then
        force_pref_down=$force_down_5g
        force_other_down=$force_down_24g
    elif [ "$pref_iface" = "$sta_iface_24g" ]; then
        force_pref_down=$force_down_24g
        force_other_down=$force_down_5g
    fi

    if ! __repacd_wifimon_is_assoc $pref_iface || \
           [ "$force_pref_down" -gt 0 ]; then
        if __repacd_wifimon_is_assoc $other_iface &&
               [ "$force_other_down" -eq 0 ]; then
            if [ "$guest_link_override" -eq 0 ]; then
                if [ "$guest_preflink_down_start_time" -eq 0 ]; then
                    __repacd_wifimon_get_timestamp guest_preflink_down_start_time
                    guest_preflink_up_start_time=0
                elif __repacd_wifimon_is_timeout $guest_preflink_down_start_time \
                         $guest_preflink_down_timeout; then
                    ifname=`iwconfig 2>&1 | grep "$other_iface.$guest_vid" | cut -d ' ' -f1`
                    if [ -z "$ifname" ]; then
                        vconfig add $other_iface $guest_vid
                    fi
                    brctl delif "br-$network_guest" "$pref_iface.$guest_vid"
                    brctl addif "br-$network_guest" "$other_iface.$guest_vid"
                    ifconfig $other_iface.$guest_vid up
                    guest_link_override=1
                fi
            fi
        elif ! __repacd_wifimon_is_assoc $other_iface || \
                 [ "$force_other_down" -gt 0 ]; then
            if [ -n "$guest_preflink_down_start_time" ]; then
                guest_preflink_down_start_time=0
            fi

            if [ "$guest_link_override" -gt 0 ]; then
                brctl delif "br-$network_guest" "$other_iface.$guest_vid"
                brctl addif "br-$network_guest" "$pref_iface.$guest_vid"
                ifconfig $pref_iface.$guest_vid up
                guest_link_override=0
            fi
        fi
    elif __repacd_wifimon_is_assoc $pref_iface &&
             [ "$force_pref_down" -eq 0 ]; then
        if [ "$guest_link_override" -gt 0 ]; then
           if [ "$guest_preflink_up_start_time" -eq 0 ]; then
               __repacd_wifimon_get_timestamp guest_preflink_up_start_time
               guest_preflink_down_start_time=0
           elif __repacd_wifimon_is_timeout $guest_preflink_up_start_time \
                    $guest_preflink_up_timeout; then
               brctl delif "br-$network_guest" "$other_iface.$guest_vid"
               brctl addif "br-$network_guest" "$pref_iface.$guest_vid"
               ifconfig $pref_iface.$guest_vid up
               guest_link_override=0
           fi
        fi
    fi
}

# Determine the 5G RSSI backhaul quality
# input $1 -- 5G RSSI value
__repacd_wifimon_independent_channel_check() {
    local rssi="$1"
    if [ "$rssi_idle_time" -eq 0 ]; then
        if [ -n "$sta_iface_24g" ]; then
            __repacd_wifimon_debug "rssi = $rssi quality_5g_rssi_level=$quality_5g_rssi_level force_down_24g=$force_down_24g force_down_5g=$force_down_5g rssi_counter=$rssi_counter"
            if [ "$rssi" -gt -95 -a "$rssi" -lt 0 ]; then
                if [ "$rssi" -gt "$quality_5g_rssi_level" ]; then
                    __repacd_wifimon_debug "rssi good then quality_5g_rssi_level"
                    if [ "$is_24G_down_by_independent_channel" -eq 0 ]; then
                        rssi_counter=$((rssi_counter + 1))
                    else
                        rssi_counter=0
                    fi
                else
                    __repacd_wifimon_debug "rssi less then quality_5g_rssi_level force_down_24g=$force_down_24g"
                    if [ "$is_24G_down_by_independent_channel" -eq 0 ]; then
                        rssi_counter=0
                    else
                        rssi_counter=$((rssi_counter + 1))
                    fi
                fi
            fi
        else
            __repacd_wifimon_debug "sta_iface_24g=$sta_iface_24g"
        fi
    else
        rssi_idle_time=$((rssi_idle_time - 1))
        __repacd_wifimon_debug "rssi_idle_time=$rssi_idle_time"
    fi
}

# Determine if the STA is associated and update the state accordingly.
# input: $1 - network: the name of the network being managed
# input: $2 - cur_re_mode: the currently configured range extender mode
# input: $3 - cur_re_submode: the currently configured range extender sub-mode
# input: $4 - whether this is a check during init for a restart triggered
#             by mode switching
# output: $5 - state: the variable to update with the new state name (if there
#                     was a change)
# output: $6 - re_mode: the desired range extender mode
# output: $7 - re_submode: the desired range extender sub-mode
# return: 0 if associated; otherwise 1
__repacd_wifimon_check_associated() {
    local network=$1
    local cur_re_mode=$2
    local cur_re_submode=$3
    local autoconf_start=$4
    local associated=0 resolving=0
    firstboot=`cat /tmp/firstboot`

    config_load repacd
    config_get bssid_resolve_state WiFiLink 'BSSIDResolveState' 'resolving'
    # In Daisy chaining, when we are at hop 2 and above, allow monitoring
    # even if single backhaul is associated provided other backhaul is forced down.
    if __repacd_wifimon_is_assoc $sta_iface_5g \
        && __repacd_wifimon_is_assoc $sta_iface_24g; then
        associated=1
    elif [ "$ignore_24g_assoc" -gt 0 ] \
        && __repacd_wifimon_is_assoc $sta_iface_5g; then
        associated=1
    elif [ "$bssid_resolve_state" = "resolving" ]; then
        if __repacd_wifimon_is_assoc $sta_iface_5g; then
            resolving=1
        elif __repacd_wifimon_is_assoc $sta_iface_24g \
            && [ "$nolink_detected_5g" -gt 0 ]; then
            resolving=1
        fi
    fi

    __repacd_wifimon_debug "  check_associated: state=$bssid_resolve_state, associated=$associated, resolving=$resolving "

    if [ "$associated" -gt 0 -o "$resolving" -gt 0 ]; then
        # Only update the LED state if we transitioned from not associated
        # to associated.
        if [ "$last_assoc_state" -eq 0 ]; then
            if [ "$wps_in_progress" -gt 0 ]; then
                # If WPS was triggered, it could take some time for the
                # interfaces to settle into their final state. Thus, update
                # the start time for the measurement to the point at which
                # the WPS button was pressed.
                assoc_start_time=$wps_start_time

                # Clear this as we only want to extend the association time
                # for this one instance. All subsequent ones should be based
                # on the time we detect a disassociation (unless WPS is
                # triggered again).
                wps_start_time=''

                # Clear this flag so that we now use the association timer
                # instead of the WPS one.
                wps_in_progress=0

                wps_stabilization=1
            elif [ "$daisy_chain" -gt 0 -a "$bssid_stabilization" -eq 0 ]; then
                if [ -n "$sta_iface_5g" -a "$force_down_5g" -eq 0 ] \
                    && __repacd_wifimon_is_assoc $sta_iface_5g; then
                    # Daisy chaining enabled, so deep cloning would have been disabled.
                    # Update the 5G BSSID, because we will proceed assuming current
                    # connection is stable.
                    if [ "$badlink_switch_inprogress" -eq 0 ]; then
                        __repacd_wifimon_config_current_bssid $sta_iface_5g $sta_iface_5g_config_name
                        bssid_resolve_complete=0
                    else
                        bssid_resolve_complete=1
                    fi

                    __repacd_wifimon_get_timestamp assoc_start_time

                    bssid_stabilization=1
                    bssid_assoc_count=0
                    assoc_timeout_logged=0

                    eval "$5=$WIFIMON_STATE_AUTOCONFIG_IN_PROGRESS"
                elif [ "$nolink_detected_5g" -gt 0 -a -n "$sta_iface_24g" -a "$force_down_24g" -eq 0 ] \
                    && __repacd_wifimon_is_assoc $sta_iface_24g; then
                    # We are here because we detected Nolink or Badlink in 5G band.
                    __repacd_wifimon_config_current_bssid $sta_iface_24g $sta_iface_24g_config_name
                    bssid_resolve_complete=0

                    __repacd_wifimon_get_timestamp assoc_start_time

                    bssid_stabilization=1
                    bssid_assoc_count=0
                    assoc_timeout_logged=0

                    eval "$5=$WIFIMON_STATE_AUTOCONFIG_IN_PROGRESS"
                fi
            elif [ "$config_re_mode" = 'auto' ] && [ "$auto_mode_stabilization" -eq 0 ]; then
                # When making mode switching decisions, we also want to allow
                # for enough time for the interfaces to stabilize.
                __repacd_wifimon_get_timestamp assoc_start_time

                auto_mode_stabilization=1
                auto_mode_assoc_count=0
                assoc_timeout_logged=0

                eval "$5=$WIFIMON_STATE_AUTOCONFIG_IN_PROGRESS"
            fi

            if [ "$wps_stabilization" -gt 0 ]; then
                wps_assoc_count=$((wps_assoc_count + 1))
                __repacd_wifimon_debug "Assoc post WPS (#$wps_assoc_count)"
            elif [ "$bssid_stabilization" -gt 0 ]; then
                if [ "$bssid_resolve_complete" -gt 0 ]; then
                    if [ "$backhaul_mode_configured" = "$backhaul_mode_single" ] && __repacd_wifimon_is_active_assoc $sta_iface_5g && __repacd_wifimon_is_active_assoc $sta_iface_24g; then
                        __repacd_wifimon_debug "Disabling 2G backhaul since AP is operating in single backhaul mode and 5G is up and running"
                        __repacd_wifimon_bring_iface_down $sta_iface_24g
                    fi
                    if [ "$firstboot" == 1 ]; then
                        __repacd_wifimon_skip_hyst_enable $sta_iface_24g
                        __repacd_wifimon_skip_hyst_enable $sta_iface_5g
                    else
                        __repacd_wifimon_skip_hyst_disable $sta_iface_24g
                        __repacd_wifimon_skip_hyst_disable $sta_iface_5g
                    fi
                    bssid_assoc_count=$((bssid_assoc_count + 1))
                    __repacd_wifimon_debug "Assoc post BSSID resolve (#$bssid_assoc_count)"
                elif [ "$cur_re_mode" = "son" -a "$bssid_resolve_state" = "resolving" ]; then
                    local otherband_sta_iface_config_name
                    # Try configuring otherband backhaul BSSID.
                    # Otherband BSSID is arrived from beacon of current associated link.
                    # If successfully configured, we are ready to enable
                    # otherband station and check for association.
                    if [ "$nolink_detected_5g" -eq 0 ]; then
                        __repacd_wifimon_find_and_config_otherband_bssid $sta_iface_5g
                        otherband_sta_iface_config_name=$sta_iface_24g_config_name
                    else
                        __repacd_wifimon_find_and_config_otherband_bssid $sta_iface_24g
                        otherband_sta_iface_config_name=$sta_iface_5g_config_name
                    fi

                    config_load wireless
                    if __repacd_wifimon_is_peer_bssid_set $otherband_sta_iface_config_name; then
                        # Marking BSSIDResolveState=resolved to indicate
                        # BSSID resolve completion.
                        uci_set repacd WiFiLink BSSIDResolveState 'resolved'
                        uci_commit repacd
                        bssid_resolve_complete=1
                    else
                        __repacd_wifimon_debug "Waiting for BSSID resolve"
                    fi
                else
                    bssid_resolve_complete=1
                fi
            elif [ "$auto_mode_stabilization" -gt 0 ]; then
                if __repacd_wifimon_is_deep_cloning_complete; then
                    auto_mode_assoc_count=$((auto_mode_assoc_count + 1))
                    __repacd_wifimon_debug "Auto mode stabilization (#$auto_mode_assoc_count)"
                else
                    __repacd_wifimon_debug "Waiting for deep cloning"
                fi
            fi

            if __repacd_wifimon_is_assoc_stable; then
                auto_mode_stabilization=0
                bssid_stabilization=0
                if [ $wps_stabilization -gt 0 ]; then
                    # Still BSSID configuration is not complete, move from WPS stabilization
                    # to BSSID configuration.
                    wps_stabilization=0
                    assoc_start_time=''
                    return 1
                fi

                # Check the mode to see if we are already in the desired mode.
                # If not, we will want to trigger the mode switch first as
                # otherwise the RSSI measurements may not be updated (due to
                # pings not going through).
                if __repacd_wifimon_resolve_mode $cur_re_mode $cur_re_submode $6 $7; then
                    eval "$5=$WIFIMON_STATE_MEASURING"
                    assoc_start_time=''
                    last_assoc_state=1

                    # If daisy chain mode is enabled, get the phyrate of the associated sta interface
                    # and calculate the min and max threshold rates from the configured percent_rate_min5G
                    # and percent_rate_max5G value.
                    if [ "$daisy_chain" -gt 0 ]; then
                        __repacd_wifimon_set_rate_measurement_iface "5g"
                    fi

                    # Restart the measurements. We do not remember any past
                    # ones as they might not reflect the current state (eg.
                    # if the root AP was moved).
                    rssi_num=0
                    rate_num=0
                else
                    # RE mode switch is required. Do not start measuring link.
                    return 0
                fi
            else
                # Pretend like we are not associated since we need it to be
                # stable.
                return 1
            fi
        fi

        # Association is considered stable. Measure the link, we measure the WiFi link
        # based on RSSI or Rate, RSSI measurement is used in star topology where we
        # know the APs location and REs placement is adjusted based on LED feedback.
        # But in Daisy chain, REs might have connected to any best link, REs auto detects
        # the best link so we will not know the position of connected AP and LED
        # feedback is not useful for the user. First make sure all sta interfaces are under
        # our control.
        if [ "$force_down_24g" -gt 0 ] \
            && __repacd_wifimon_is_active_assoc $sta_iface_24g; then
            __repacd_wifimon_info "Bringing down 2G Due to force down!"
            __repacd_wifimon_bring_iface_down $sta_iface_24g
        fi

        if [ "$force_down_5g" -gt 0 ] \
            && __repacd_wifimon_is_active_assoc $sta_iface_5g; then
            __repacd_wifimon_info "Bringing down 5G Due to force down!"
            __repacd_wifimon_bring_iface_down $sta_iface_5g
        fi

        # Waiting for 2.4G backhaul to associate in case of badlink.
        # Bring down 5G backhaul once 2.4G is associated and stable.
        if [ "$badlink_switch_inprogress" -gt 0 ] \
            && __repacd_wifimon_is_assoc $sta_iface_24g; then
            __repacd_wifimon_info "Bringing down 5G due to bad link"
            __repacd_wifimon_bring_iface_down $sta_iface_5g
            badlink_switch_inprogress=0
            badlink_start_time_5g=''
        fi

        if [ "$daisy_chain" -gt 0 -a "$force_down_5g" -eq 0 ]; then
            # Measure the link rate, so that we trigger the best link selection logic.
            if [ "$rate_num" -le "$rate_samples" ] && \
                __repacd_start_ping $network; then
                __repacd_wifimon_measure_rate $network $5
                return 0
            else
                # Restart the rate measurement
                rate_num=0
                #make sure it can continue to check the RSSI
                if [ "$is_independent_channel_selection_enable" -gt 0 ] &&\
                __repacd_start_ping $network; then
#                    __repacd_wifimon_independent_channel_check`iwconfig $sta_iface_5g | grep 'Signal level' | awk -F'=' '{print $3}' | awk '{print $1}'`
                    __repacd_wifimon_independent_channel_check`repacdcli $sta_iface_5g get_signal`
                fi
            fi

        else
            if [ "$force_down_5g" -gt 0 ]; then
                eval "$5=$WIFIMON_STATE_RE_MOVE_CLOSER"
                return 0;
            fi

            # Association is considered stable. Measure the link RSSI.
            if [ "$rssi_num" -le "$rssi_samples" ] && \
                __repacd_start_ping $network; then
                __repacd_wifimon_measure_link $network $5
            else
                #make sure it can continue to check the RSSI
                if [ "$is_independent_channel_selection_enable" -gt 0 ] &&\
                      __repacd_start_ping $network; then
#                    __repacd_wifimon_independent_channel_check `iwconfig $sta_iface_5g | grep 'Signal level' | awk -F'=' '{print $3}' | awk '{print $1}'`
                    __repacd_wifimon_independent_channel_check `repacdcli $sta_iface_5g get_signal`
                fi
            fi
        fi
        return 0
    # All cases below are for not associated.
    elif [ "$autoconf_start" -gt 0 ]; then
        # When making mode switching decisions, we also want to allow
        # for enough time for the interfaces to stabilize.
        __repacd_wifimon_get_timestamp assoc_start_time

        auto_mode_stabilization=1
        auto_mode_assoc_count=0
        assoc_timeout_logged=0

        eval "$5=$WIFIMON_STATE_AUTOCONFIG_IN_PROGRESS"
    elif [ "$wps_in_progress" -eq 0 -a "$wps_stabilization" -eq 0 -a \
           "$auto_mode_stabilization" -eq 0 -a "$bssid_stabilization" -eq 0 ]; then
        # Record the first time we detected ourselves as not being associated.
        # This will drive a timer in the check function that will change the
        # state if we stay disassociated for too long.
        if [ -z "$assoc_start_time" ]; then
            __repacd_wifimon_get_timestamp assoc_start_time
        fi
        if [ "$is_independent_channel_selection_enable" -gt 0 ];then
            if  __repacd_wifimon_is_assoc $sta_iface_5g && \
            __repacd_start_ping $network; then
#            __repacd_wifimon_independent_channel_check `iwconfig $sta_iface_5g | grep 'Signal level' | awk -F'=' '{print $3}' | awk '{print $1}'`
            __repacd_wifimon_independent_channel_check `repacdcli $sta_iface_5g get_signal`
            fi
        else
            __repacd_stop_ping
        fi
        last_assoc_state=0
        eval "$5=$WIFIMON_STATE_NOT_ASSOCIATED"
        # Running bestuplink for 2g in case 5g not found in boot or 5g disconnect abrubtly
        # only in single backhaul mode to skip assoc timeout for single backhaul mode
        if [ "$backhaul_mode_configured" = "$backhaul_mode_single" ] && \
            ! __repacd_wifimon_is_active_assoc $sta_iface_5g && ! __repacd_wifimon_is_active_assoc $sta_iface_24g; then
            __repacd_wifimon_debug "AP is operating in single backhaul mode but 5g was disconnected. Enabling 2g for failsafe"
            __repacd_wifimon_bring_iface_up $sta_iface_24g
        fi
    elif [ "$wps_in_progress" -gt 0 -o "$auto_mode_stabilization" -gt 0 \
        -o "$bssid_stabilization" -gt 0 ]; then
        if [ "$wps_timeout_logged" -eq 0 -a "$assoc_timeout_logged" -eq 0 ]; then
            # Suppress logs after we've timed out
            __repacd_wifimon_debug "Auto config in progress - not assoc"
            if [ "$backhaul_mode_configured" = "$backhaul_mode_single" ] && __repacd_wifimon_is_active_assoc $sta_iface_5g && ! __repacd_wifimon_is_active_assoc $sta_iface_24g; then
                __repacd_wifimon_debug "Ignoring Auto config since AP is operating in single backhaul mode"
                ignore_24g_assoc=1
            fi
            # Adding check to bringup 2g in case 5g randomly disconnects
            # during stabilization process
            if [ "$backhaul_mode_configured" = "$backhaul_mode_single" ] && \
                ! __repacd_wifimon_is_active_assoc $sta_iface_5g && ! __repacd_wifimon_is_active_assoc $sta_iface_24g; then
                __repacd_wifimon_debug "5g backhaul disconnected during stabilization. Enabling 2g for failsafe"
                __repacd_wifimon_bring_iface_up $sta_iface_24g
            fi
        fi

        bssid_assoc_count=0
        wps_assoc_count=0
        auto_mode_assoc_count=0
    fi

    # Not associated and WPS is in progress. No LED update.
    return 1
}

# Check whether the given WHC feature is advertised by the AP on which the
# given STA interface is connected.
# input: $1 - sta_iface: the interface to check for the AP capabilities
# input: $2 - ioctl_name: the name of the private ioctl to use to check the
#                         feature
# return: 0 if the feature is on or the interface name is invalid; otherwise 1
__repacd_wifimon_is_whc_feature_on_iface() {
    local sta_iface=$1
    local ioctl_name=$2
    local command_result

    if [ -z "$sta_iface" ]; then
        return 0
    fi

    if [ "$sta_iface" = "$sta_iface_5g" ] &&
           [ "$force_down_5g" -gt 0 ]; then
        return 0
    elif [ "$sta_iface" = "$sta_iface_24g" ] &&
           [ "$force_down_24g" -gt 0 -o "$ignore_24g_assoc" -gt 0 ]; then
        return 0
    fi

    if [ -z $REPACD_CFG80211 ]; then
        command_result=$(iwpriv $sta_iface $ioctl_name)
    else
        command_result=$(cfg80211tool $sta_iface $ioctl_name)
    fi
    __repacd_wifimon_dump_cmd "$ioctl_name on $sta_iface: $command_result"

    if [ -n "$command_result" ]; then
        local feature_enabled
        feature_enabled=$(echo "$command_result" | cut -d: -f2)
        if [ "$feature_enabled" -gt 0 ]; then
            return 0
        fi
    else
        __repacd_wifimon_debug "iwpriv failed on $sta_iface for $ioctl_name"
    fi

    # Feature must not be enabled or we cannot resolve it.
    return 1
}

# Determine if the serving AP has WDS enabled or not on all valid interfaces.
# return: 0 if it does have WDS enabled; otherwise 1
__repacd_wifimon_is_serving_ap_wds() {
    if __repacd_wifimon_is_whc_feature_on_iface "$sta_iface_24g" 'get_whc_wds' &&
       __repacd_wifimon_is_whc_feature_on_iface "$sta_iface_5g" 'get_whc_wds'; then
        return 0
    fi

    return 1
}

# Determine if the serving AP has SON mode enabled or not.
# return: 0 if it does have SON enabled; otherwise 1
# Added retries to make sure both the sta interafces are up
# since there are chances that during config change RE might
# be going through wifi reload
__repacd_wifimon_is_serving_ap_son() {
    local retries=6

    while [ "$retries" -gt 0 ]; do
        if __repacd_wifimon_is_whc_feature_on_iface "$sta_iface_24g" 'get_whc_son' &&
            __repacd_wifimon_is_whc_feature_on_iface "$sta_iface_5g" 'get_whc_son'; then
        return 0
        else
            sleep 5
            retries=$((retries -1))
        fi
    done
    return 1
}

# Determine if the serving AP has SON mode enabled and it is an RE.
# return: 0 if it is RE and does have SON enabled; otherwise 1
__repacd_wifimon_is_serving_ap_daisy_son() {
    if [ "$daisy_chain" -gt 0 ] \
        && __repacd_wifimon_is_whc_feature_on_iface "$sta_iface_5g" 'get_whc_son'; then
        __repacd_get_root_ap_dist $sta_iface_5g root_distance
        if [ "$root_distance" -gt 1 ]; then
            return 0
        fi
    fi

    return 1
}

# Determine the number of hops a given STA interface is from the
# root AP.
# input: $1 - sta_iface: the name of the STA interface (eg. ath01)
# output: $2 - dist: the distance (in terms of hops) from the root AP
__repacd_get_root_ap_dist() {
    local sta_iface=$1

    local command_result

    if [ -z "$sta_iface" ]; then
        return 0
    fi


    if [ -z $REPACD_CFG80211 ]; then
        command_result=$(iwpriv $sta_iface get_whc_dist)
    else
        command_result=$(cfg80211tool $sta_iface get_whc_dist)
    fi
    __repacd_wifimon_dump_cmd "root dist for $sta_iface: $command_result"

    if [ -n "$command_result" ]; then
        local root_dist
        root_dist=$(echo "$command_result" | cut -d: -f2)
        eval "$2=$root_dist"
    fi
}

# Determine the maximum number of hops the STA interfaces are from the
# root AP.
# output: $1 - max_dist: the maximum distance (in terms of hops) from the
#                       root AP
__repacd_get_max_root_ap_dist() {
    local root_dist_24g=0 root_dist_5g=0
    if [ -n "$sta_iface_24g" ]; then
        __repacd_get_root_ap_dist $sta_iface_24g root_dist_24g
    fi

    if [ -n "$sta_iface_5g" ]; then
        __repacd_get_root_ap_dist $sta_iface_5g root_dist_5g
    fi

    # If daisy chaining enabled and 5G is active,
    # determine root distance from 5G only.
    if [ "$daisy_chain" -gt 0 ] \
        && [ -n "$sta_iface_5g" -a "$force_down_5g" -eq 0 ]; then
            eval "$1=$root_dist_5g"
    else
        if [ "$root_dist_24g" -eq $RE_ROOT_AP_DISTANCE_INVALID ]; then
            eval "$1=$root_dist_5g"
            return
        elif [ "$root_dist_5g" -eq $RE_ROOT_AP_DISTANCE_INVALID ]; then
            eval "$1=$root_dist_24g"
            return
        fi
        if [ "$root_dist_24g" -gt "$root_dist_5g" ]; then
            eval "$1=$root_dist_24g"
        else
            eval "$1=$root_dist_5g"
        fi
    fi
}

# Determine if the serving AP is currently the CAP or not.
# return: 0 if associated to the CAP; otherwise 1
__repacd_wifimon_is_cap_serving() {
    # If the root AP is not operating in WDS mode, it may not even be a WHC
    # AP. To be conservative, we do not enable the AP functionality.
    local wds_enabled root_dist

    if __repacd_wifimon_is_serving_ap_wds; then
        __repacd_get_max_root_ap_dist root_dist
        if [ "$root_dist" -eq 1 ]; then
            # The STA device saying it is 1 hop away means that the serving
            # AP indicated it was 0 hops away from the CAP. This means that
            # the serving AP is the CAP.
            return 0
        fi
    else
        __repacd_wifimon_debug "Serving AP is not WHC enabled"
    fi

    # Either we are more than 1 hop from the root or the distance is
    # unknown. In either case, indicate that the CAP is not serving.
    return 1
}

# Determine the minimum number of hops the STA interfaces are from the
# root AP.
# output: $1 - min_dist: the minimum distance (in terms of hops) from the
#                       root AP
__repacd_get_min_root_ap_dist() {
    local root_distance_24g=$RE_ROOT_AP_DISTANCE_INVALID
    local root_distance_5g=$RE_ROOT_AP_DISTANCE_INVALID

    if [ -n "$sta_iface_5g" ]; then
        __repacd_get_root_ap_dist $sta_iface_5g root_distance_5g
    fi
    if [ -n "$sta_iface_24g" ]; then
        __repacd_get_root_ap_dist $sta_iface_24g root_distance_24g
    fi

    if [ "$root_distance_24g" -le "$root_distance_5g" ]; then
        eval "$1=$root_distance_24g"
    else
        eval "$1=$root_distance_5g"
    fi
}

# Set the Root AP distance based on STA association state to AP interface.
# input $1: config: interface configuration name
# input $2: distance: new root distance to configure on AP interface
__repacd_wifimon_set_root_distance() {
    local config=$1
    local distance=$2
    local iface mode

    config_get mode "$config" mode
    config_get iface $config ifname

    if [ "$mode" = "ap" ]; then
        if [ -z $REPACD_CFG80211 ]; then
            iwpriv $iface set_whc_dist $distance
        else
            cfg80211tool $iface set_whc_dist $distance
        fi
    fi
}

# Copy the Uplink rate from associated STA to non associated STA.
# input $1: source_iface: source(associated) interface name to get rate
# input $2: target_iface: target(non-associated) interface name to set rate
__repacd_wifimon_copy_uplink_rate() {
    local src_iface=$1
    local tgt_iface=$2
    local src_rate

    if [ -n "$src_iface" -a -n "$tgt_iface" ] \
        && __repacd_wifimon_is_assoc $src_iface; then
        if [ -z $REPACD_CFG80211 ]; then
            src_rate=`iwpriv $src_iface get_whc_ul_rate | awk -F':' '{print $2}'`
            iwpriv $tgt_iface set_whc_ul_rate $src_rate
        else
            src_rate=`cfg80211tool $src_iface get_whc_ul_rate | awk -F':' '{print $2}'`
            cfg80211tool $tgt_iface set_whc_ul_rate $src_rate
        fi
    fi
}

# Set the desired Uplink rate for the provided interace.
# input $1: iface: interface name to get rate
# input $2: rate: rate to set
__repacd_wifimon_set_uplink_rate() {
    local iface=$1
    local rate=$2

    if [ -n "$iface" ]; then
        if [ -z $REPACD_CFG80211 ]; then
            iwpriv $iface set_whc_ul_rate $rate
        else
            cfg80211tool $iface set_whc_ul_rate $rate
        fi
    fi
}

# Determine the current SON sub-mode.
# output: $1 - submode: sub mode we are operating in.
__repacd_wifimon_get_son_submode() {
    if __repacd_wifimon_is_cap_serving; then
        eval "$1=star"
    else
        eval "$1=daisy"
    fi
}

# Disable hysteresis in  sta vap interface.
# input: $1 - sta interface: the name of the interface disable hysteresis for bestuplink in driver.
__repacd_wifimon_skip_hyst_disable() {

    local sta_iface=$1
    if [ -n "$sta_iface" ];then
        if [ -z $REPACD_CFG80211 ]; then
            iwpriv $sta_iface set_skip_hyst 0
        else
            cfg80211tool $sta_iface set_skip_hyst 0
        fi
    fi
}

# Enable hysteresis in  sta vap interface.
# input: $1 - sta interface: the name of the interface Enable hysteresis for bestuplink in driver.
__repacd_wifimon_skip_hyst_enable() {

    local sta_iface=$1
    if [ -n "$sta_iface" ];then
        if [ -z $REPACD_CFG80211 ]; then
            iwpriv $sta_iface set_skip_hyst 1
        else
            cfg80211tool $sta_iface set_skip_hyst 1
        fi
    fi
}

# Bring down sta vap interface.
# input: $1 - sta interface: the name of the interface for bringing down.
__repacd_wifimon_bring_iface_down() {


    local sta_iface=$1
    if [ -n "$sta_iface" ];then
        network_id=`wpa_cli -p /var/run/wpa_supplicant-$sta_iface list_network | grep CURRENT | awk '{print $1}'`
        if [ -z  $network_id ]; then
            network_id=0
        fi
        __repacd_wifimon_info "Interface $sta_iface Brought down with network id $network_id"
        xqwhc_repacd_sync_lock lock $sta_iface
        if [ "$sta_iface" = "$sta_iface_5g" ]; then
            force_down_5g=1
            if [ -n "$force_down_5g_timestamp" ] ;then
                backhaul_eval_time=$config_long_eval_time5g
            else
                backhaul_eval_time=$config_short_eval_time5g
            fi
            __repacd_wifimon_get_timestamp force_down_5g_timestamp
        else
            force_down_24g=1
        fi
        rssi_counter=0

        wpa_cli -p /var/run/wpa_supplicant-$sta_iface disable_network $network_id
        xqwhc_repacd_sync "${XQWHC_REPACD_IFDOWN}_${sta_iface}" 1
        xqwhc_repacd_sync_lock unlock $sta_iface

        # miwifi: also down ifconfig
        #ifconfig $sta_iface down 2>/dev/null
    fi
}

# Bring up sta vap interface.
# input: $1 - sta interface: the name of the interface for bringing up.
__repacd_wifimon_bring_iface_up() {
    local sta_iface=$1

    if [ -n "$sta_iface" ];then
        network_id=`wpa_cli -p /var/run/wpa_supplicant-$sta_iface list_network | grep DISABLED | awk '{print $1}'`
        if [ -z  $network_id ]; then
            network_id=0
        fi
        __repacd_wifimon_info "Interface $sta_iface Brought up with network id $network_id"
        if [ "$backhaul_mode_configured" = "$backhaul_mode_single" ]; then
            [ ! -f /etc/init.d/wsplcd ] || /etc/init.d/wsplcd restart
        fi
        xqwhc_repacd_sync_lock lock $sta_iface
        if [ "$sta_iface" = "$sta_iface_5g" ]; then
            force_down_5g=0
        else
            force_down_24g=0
            #if 2.4G interface up, force reset independent_channel parameters to 0
            is_24G_down_by_independent_channel=0
            uci_set wireless $wifi_2G_interface_name independent_channel_set '0'
            uci_commit wireless
        fi
        rssi_counter=0
        last_assoc_state=0

        wpa_cli -p /var/run/wpa_supplicant-$sta_iface enable_network $network_id
        xqwhc_repacd_sync "${XQWHC_REPACD_IFDOWN}_${sta_iface}" 0
        xqwhc_repacd_sync_lock unlock $sta_iface

        # miwifi: also up ifconfig
        #ifconfig $sta_iface up 2>/dev/null
    fi
}

# Find the median from the samples file.
# Find the median from the samples file.
# This is a crude way to compute the median when the number of
# samples is odd. It is not strictly correct for an even number
# of samples since it does not compute the average of the two
# samples in the middle and rather just takes the lower one, but
# this should be sufficient for our purposes. The average is not
# performed due to the values being on the logarithmic scale and
# because shell scripts do not directly support floating point
# arithmetic.
# input: $1 - Samples filename
# input: $2 - Number of samples in the samples file
# output: $3 - computed Median
__repacd_wifimon_compute_median() {
    local median median_index
    local samples_filename="$1"

    median_index=$((($2 + 1) / 2))
    median=$(cat $samples_filename | sort -n |
                        head -n $median_index | tail -n 1)

    eval "$3=$median"
}

# Find the maximum duplicated entry from the samples file.
# input: $1 - Samples filename
# output: $2 - Maximum duplicated entry
__repacd_wifimon_get_max_duplicated_entry() {
    local max_duplicated
    local samples_filename="$1"

    max_duplicated="$(cat $samples_filename | sort -n |
                        uniq -c | sort -nr | head -n 1 |
                        awk -F " " '{print $2}')"

    eval "$2='$max_duplicated'"
}

# Parse the provided BSSID list and set Best BSSID variables.
# input: $1 - best_bssid_list
__repacd_wifimon_parse_best_bssid_list() {
    local best_bssid_list="$1"

    __repacd_wifimon_info "Best BSSID list: "$best_bssid_list""
    new_bestap=`echo "$best_bssid_list" | awk -F ";" '{print $1}'`
    new_bestap_otherband=`echo "$best_bssid_list" | awk -F ";" '{print $2}'`
}

# Measure the Rate to the serving AP and update the state accordingly.
# input: $1 - network: the name of the network being monitored
# output: $2 - state: the variable to update with the new state name (if there
#                     was a change)
__repacd_wifimon_measure_rate() {
    local bestap bestap_otherband
    local rssi uplink_snr CAP_snr my_uplink_rate
    ob_bssid=`uci show wireless | grep "bssid=" | cut -d= -f 2 | awk 'NR==2' | awk -F "'" '{print $2}'`

    # Just check Gateway link and proceed to rate measurement.
    if ! __repacd_is_gw_reachable; then
        if [ -n "$last_ping_gw_ip" ]; then
            __repacd_wifimon_debug "GW ${last_ping_gw_ip} not reachable"
        else
            __repacd_wifimon_debug "GW unknown"
        fi
    fi

    # Get the 5G RSSI level
#    rssi=`iwconfig $sta_iface_5g | grep 'Signal level' | awk -F'=' '{print $3}' | awk '{print $1}'`
    rssi=`repacdcli $sta_iface_5g get_signal`
    # Get the UPLINK SNR
    uplink_snr=`cfg80211tool $measurement_sta_iface get_whc_ul_snr | awk -F':' '{print $2}'`

    # Only the 5 GHz link is measured. This is especially done since we
    # generally cannot control which interface is used to reach upstream.
    # Generally 5 GHz will be used (per the rules to set the broadcast bit
    # and choose a default path), so we may not have any valid Rate data on
    # 2.4 GHz.

    if [ -z $REPACD_CFG80211 ]; then
        # Get the rate to CAP estimate.
        rate_to_CAP=`iwpriv $measurement_sta_iface get_whc_rate | awk -F':' '{print $2}'`
        # Get the uplink rate with connected node.
        my_uplink_rate=`iwpriv $measurement_sta_iface get_whc_ul_rate | awk -F':' '{print $2}'`
        # Get the current CAP SNR.
        CAP_snr=`iwpriv $measurement_sta_iface g_curr_caprssi | awk -F':' '{print $2}'`
    else
        # Get the rate to CAP estimate.
        rate_to_CAP=`cfg80211tool $measurement_sta_iface get_whc_rate | awk -F':' '{print $2}'`
        # Get the uplink rate with connected node.
        my_uplink_rate=`cfg80211tool $measurement_sta_iface get_whc_ul_rate | awk -F':' '{print $2}'`
        # Get the current CAP SNR.
        CAP_snr=`cfg80211tool $measurement_sta_iface g_curr_caprssi | awk -F':' '{print $2}'`
    fi
    # Get the current Best AP, later it will be used for finding the Best AP
    # once the measurement is completed.
    __repacd_wifimon_get_current_best_ap $measurement_sta_iface bestap bestap_otherband

    if [ "$is_independent_channel_selection_enable" -gt 0 ]; then
        # Only the 5 GHz link is measured. This is especially done since we
        # generally cannot control which interface is used to reach upstream.
        # Generally 5 GHz will be used (per the rules to set the broadcast bit
        # and choose a default path), so we may not have any valid RSSI data on
        # 2.4 GHz.
        __repacd_wifimon_independent_channel_check $rssi
    fi
    # We explicitly ignore clearly bogus values. 0 Mbps seen in
    # some instances where the STA is not associated by the time the Rate
    # check is done.
    ob_bssid=`uci show wireless | grep "bssid=" | cut -d= -f 2 | awk 'NR==2' | awk -F "'" '{print $2}'`

    if [ "$rate_num" -eq 0 ]; then
        if [ "$measuring_cnt" -gt 0 ]; then
            __repacd_wifimon_debug "Measurement failed attempt # $measuring_cnt"
        fi
        measuring_cnt=$((measuring_cnt + 1))
    fi

    if [ "$measuring_cnt" -gt "$measuring_attempts" ]; then
        if [ -n "$sta_iface_24g" ] &&
                __repacd_wifimon_is_assoc $sta_iface_24g ; then
                __repacd_wifimon_bring_iface_down $sta_iface_5g
            measuring_cnt=0
            eval "$2=$WIFIMON_STATE_RE_MOVE_CLOSER"
            return
        fi
    fi

    if [ "$snr_enabled" == "1" ]; then
        uplink_rssi_snr="Uplink snr = $uplink_snr"
    else
        uplink_rssi_snr="RSSI = $rssi"
    fi

    if [ -n "$rate_to_CAP" ]; then
        if [ "$rate_num" -lt "$rate_samples" ]; then
            # We explicitly disable 2g Backhaul if AP is operating in single backhaul mode
            # if 5g connected rate is greater than 0 then disable 2g backhaul using supplicant
            # if 5g connected rate is equal to 0 then enable 2g backahul using supplicant
            if [ "$backhaul_mode_configured" = "$backhaul_mode_single" ]; then
                if __repacd_wifimon_is_active_assoc $sta_iface_5g && __repacd_wifimon_is_active_assoc $sta_iface_24g; then
                    __repacd_wifimon_debug "AP In single backhaul mode & 5g is connected hence disabling 2g Backahul"
                    __repacd_wifimon_bring_iface_down $sta_iface_24g
                    __repacd_wifimon_debug "Sample #$rate_num $uplink_rssi_snr Rate to CAP = $rate_to_CAP Mbps"
                elif ! __repacd_wifimon_is_active_assoc $sta_iface_5g; then
                    __repacd_wifimon_debug "5g backhaul broken/low $uplink_rssi_snr during bestuplink- Enabling 2g Backahul since AP is operating in single backhaul mode"
                    __repacd_wifimon_find_and_config_otherband_bssid $sta_iface_24g
                    __repacd_wifimon_bring_iface_up $sta_iface_24g
                    __repacd_wifimon_debug "Sample #$rate_num $uplink_rssi_snr Rate to CAP = $rate_to_CAP Mbps"
                else
                    __repacd_wifimon_debug "Sample #$rate_num $uplink_rssi_snr Rate to CAP = $rate_to_CAP Mbps"
                fi
            else
                __repacd_wifimon_debug "Sample #$rate_num $uplink_rssi_snr Rate to CAP = $rate_to_CAP Mbps"
            fi
            # Ignore the very first sample since it is taken at the same time
            # the ping is started (and thus the Rate might not have been
            # updated).
            if [ "$rate_num" -eq 0 ]; then
                rssi_filename=`mktemp /tmp/repacd-rssi.XXXXXX`
                uplink_snr_filename=`mktemp /tmp/repacd-uplink-snr.XXXXXX`
                rate_to_CAP_filename=`mktemp /tmp/repacd-rate-toCAP.XXXXXX`
                CAP_snr_filename=`mktemp /tmp/repacd-CAP-snr.XXXXXX`
                bestap_filename=`mktemp /tmp/repacd-bestap.XXXXXX`
                if [ -n "$sta_iface_24g" ]; then
                    my_uplink_rate_filename=`mktemp /tmp/repacd-rate-myUplink.XXXXXX`
                fi
            else
                # Not the first sample
                echo $rssi >> $rssi_filename
                echo $uplink_snr >> $uplink_snr_filename
                echo $rate_to_CAP >> $rate_to_CAP_filename
                echo $CAP_snr >> $CAP_snr_filename
                echo "$bestap;$bestap_otherband" >> $bestap_filename
                if [ -n "$sta_iface_24g" ]; then
                    echo $my_uplink_rate >> $my_uplink_rate_filename
                fi
            fi
        elif [ "$rate_num" -eq "$rate_samples" ]; then
            __repacd_wifimon_debug "Sample #$rate_num $uplink_rssi_snr Rate to CAP = $rate_to_CAP Mbps"
            measuring_cnt=0
            # We will take one more sample and then draw the conclusion.
            # No further measurements will be taken (although this may be
            # changed in the future).
            echo $rssi >> $rssi_filename
            echo $uplink_snr >> $uplink_snr_filename
            echo $rate_to_CAP >> $rate_to_CAP_filename
            echo $CAP_snr >> $CAP_snr_filename
            echo "$bestap;$bestap_otherband" >> $bestap_filename
            if [ -n "$sta_iface_24g" ]; then
                echo $my_uplink_rate >> $my_uplink_rate_filename
            fi

            # We got the required number of samples, now derive the median rate.
            local rssi_median uplink_snr_median rate_to_CAP_median my_uplink_rate_median CAP_snr_median bestap_bssid_list restarted=0 config_success=0
            __repacd_wifimon_compute_median $rssi_filename $rate_num rssi_median
            __repacd_wifimon_compute_median $uplink_snr_filename $rate_num uplink_snr_median
            __repacd_wifimon_compute_median $rate_to_CAP_filename $rate_num rate_to_CAP_median
            __repacd_wifimon_compute_median $CAP_snr_filename $rate_num CAP_snr_median
            __repacd_wifimon_info "Median: Uplink_snr = $uplink_snr_median RSSI = $rssi_median Rate to CAP = $rate_to_CAP_median Mbps"
            firstboot=`cat /tmp/firstboot`
            if [ "$device_type" = 'RE' ]; then
                # Set the LED state
                if [ $rssi_median -lt $rssi_far ]; then
                    eval "$2=$WIFIMON_STATE_RE_MOVE_CLOSER"
                elif [ $rssi_median -gt $rssi_near ]; then
                    eval "$2=$WIFIMON_STATE_RE_MOVE_FARTHER"
                else
                    eval "$2=$WIFIMON_STATE_RE_LOCATION_SUITABLE"
                fi

                # Check if CAP SNR is greater than CAP SNR threshold, if greater then
                # Connect to CAP and ignore rate measurement result.
                if [ $CAP_snr_threshold -gt 0 -a $CAP_snr_median -ge $CAP_snr_threshold ]; then
                    __repacd_wifimon_get_max_duplicated_entry $bestap_filename bestap_bssid_list
                    __repacd_wifimon_parse_best_bssid_list "$bestap_bssid_list"
                    __repacd_wifimon_config_best_ap $measurement_sta_iface $measurement_sta_iface_config_name restarted config_success
                    if [ "$restarted" -gt 0 ]; then
                        __repacd_wifimon_debug "CAP SNR >= $CAP_snr_threshold, Connecting to CAP"
                    fi
                else
                    if __repacd_wifimon_is_cap_serving \
                        && [ $CAP_snr_threshold -gt 0 -a $CAP_snr_median -ge $MoveFromCAP_snr_threshold ]; then
                        __repacd_wifimon_debug "Stay connected to CAP, CAP SNR is good"
                    else
                        __repacd_wifimon_is_cap_serving && topo="star" || topo="daisy"

                        if [ "$rate_to_CAP_median" -lt "$rate_min" ] || [ "$rate_to_CAP_median" -gt "$rate_max" ] || [ "$firstboot" == 1 ]; then
                            __repacd_wifimon_info "connected as $topo, rate_to_CAP_median:$rate_to_CAP_median, rate_min:$rate_min, rate_max:$rate_max, firstboot:$firstboot. switch to bestBSSID list."
                            __repacd_wifimon_get_max_duplicated_entry $bestap_filename bestap_bssid_list
                            __repacd_wifimon_parse_best_bssid_list "$bestap_bssid_list"
                            __repacd_wifimon_config_best_ap $measurement_sta_iface $measurement_sta_iface_config_name restarted config_success
                            if [ "$firstboot" == 1 ]; then
                                echo 0 > /tmp/firstboot
                                __repacd_wifimon_skip_hyst_disable $sta_iface
                            fi
                        fi
                    fi
                fi
            fi

            backhaul_below_threshold=0
            if [ "$snr_enabled" == "1" ]; then
                [ -n "$uplink_snr_median" -a "$uplink_snr_median"  -lt "$snr_pref2G" ] && backhaul_below_threshold=1
                uplink_rssi_snr="snr"
            else
                [ -n "$rssi_median" -a "$rssi_median" -lt "$rssi_pref2G" ] && backhaul_below_threshold=1
                uplink_rssi_snr="rssi"
            fi

            # If 5G link is very bad and below the prefered limit,
            # switch to 2.4G backhaul link.
            # If AP is operating in single backhaul mode 2g would have been disabled
            # In that case we check if AP is operating in single backhaul mode & enable 2g backhaul
            # because of bad link & then bring down 5g backhaul
            if [ "$restarted" -eq 0 ]; then
                if [ -n "$sta_iface_24g" ]; then
                    __repacd_wifimon_compute_median $my_uplink_rate_filename $rate_num my_uplink_rate_median

                    if [ "$backhaul_below_threshold" == "1" ];then
                        if [ "$backhaul_mode_configured" = "$backhaul_mode_single" ] ; then
                                __repacd_wifimon_info "Enabling 2g backhaul because of bad 5g backhaul link & enabling Eval timer"
                                __repacd_wifimon_find_and_config_otherband_bssid $sta_iface_24g
                                __repacd_wifimon_bring_iface_up $sta_iface_24g
                                sleep 15
                                if  __repacd_wifimon_is_assoc $sta_iface_24g;then
                                    __repacd_wifimon_info "Bringing down 5G Due to Bad $uplink_rssi_snr since 2g backhaul brought up and connected as backup link"
                                    __repacd_wifimon_bring_iface_down $sta_iface_5g
                                    __repacd_wifimon_get_timestamp assoc_start_time
                                else
                                    __repacd_wifimon_bring_iface_down $sta_iface_24g
                                    __repacd_wifimon_info " 2G Backhaul not connected in given time & continuing with 5G Backhaul"
                                fi
                        else
                            if  __repacd_wifimon_is_assoc $sta_iface_24g;then
                                __repacd_wifimon_info "Bringing down 5G Due to Bad $uplink_rssi_snr"
                                __repacd_wifimon_bring_iface_down $sta_iface_5g
                                __repacd_wifimon_get_timestamp assoc_start_time
                            fi
                        fi
                    elif [ "$my_uplink_rate_median" -lt "$rate_pref2G" ]; then
                        # Start the 5G bad link timer, if not started before.
                        if [ -z "$badlink_start_time_5g" ]; then
                            __repacd_wifimon_get_timestamp badlink_start_time_5g
                        elif __repacd_wifimon_is_timeout $badlink_start_time_5g $badlink_timeout5G; then
                            # Bring up 2.4G link if forced down before and wait for association
                            # and then disable 5G backhaul link. 5G backhaul will be
                            # back when the 2.4G link goes down or 5G evaluation timedout.
                            __repacd_wifimon_info "Median My uplink rate = $my_uplink_rate_median Mbps"
                            __repacd_wifimon_info "Bad 5G link detected, will bring down 5G once 2.4G is UP"
                            if [ "$force_down_24g" -gt 0 ]; then
                                __repacd_wifimon_bring_iface_up $sta_iface_24g
                            else
                                __repacd_wifimon_info " 5G badlink timeout, check sta_iface_24g is up"
                            fi
                            badlink_switch_inprogress=1
                            badlink_start_time_5g=''
                        fi
                    elif [ "$my_uplink_rate_median" -ge "$rate_pref2G" ]; then
                        # We detected good link in 5G, disable the timer.
                        badlink_start_time_5g=''
                    fi
                fi
            else
                # If VAP was restarted, restart the BSSID stabilization.
                last_assoc_state=0
                badlink_switch_inprogress=0
                badlink_start_time_5g=''
            fi

            # We detected a link in 5G, clear the no-link flag.
            if [ "$nolink_detected_5g" -gt 0 ]; then
                nolink_detected_5g=0
            fi

            # We have our measurement, so the ping is no longer needed.
            __repacd_stop_ping

            # In case we disassociate after this, we will want to start the
            # association timer again, so clear our state of the last time we
            # started it so that it can be started afresh upon disassociation.
            assoc_start_time=''
        fi
        rate_num=$((rate_num + 1))
    fi
}

# Measure the RSSI to the serving AP and update the state accordingly.
# input: $1 - network: the name of the network being monitored
# output: $2 - state: the variable to update with the new state name (if there
#                     was a change)
__repacd_wifimon_measure_link() {
    local rssi

    if ! __repacd_is_gw_reachable; then
        if [ -n "$last_ping_gw_ip" ]; then
            __repacd_wifimon_debug "GW ${last_ping_gw_ip} not reachable"
        else
            __repacd_wifimon_debug "GW unknown"
        fi
        return
    fi

    if [ "$rssi_num" -eq 0 ]; then
        if [ "$measuring_cnt" -gt 0 ]; then
            __repacd_wifimon_debug "Measurement failed attempt # $measuring_cnt"
        fi
        measuring_cnt=$((measuring_cnt + 1))
    fi

    if [ "$measuring_cnt" -gt "$measuring_attempts" ]; then
        if [ -n "$sta_iface_24g" ] &&
               __repacd_wifimon_is_assoc $sta_iface_24g ; then
            __repacd_wifimon_info "Bringing down 5G Due to exceed measuring_attempts!"
            __repacd_wifimon_bring_iface_down $sta_iface_5g
            measuring_cnt=0
            eval "$2=$WIFIMON_STATE_RE_MOVE_CLOSER"
            return
        fi
    fi

    # Only the 5 GHz link is measured. This is especially done since we
    # generally cannot control which interface is used to reach upstream.
    # Generally 5 GHz will be used (per the rules to set the broadcast bit
    # and choose a default path), so we may not have any valid RSSI data on
    # 2.4 GHz.
#    rssi=`iwconfig $sta_iface_5g | grep 'Signal level' | awk -F'=' '{print $3}' | awk '{print $1}'`
    rssi=`repacdcli $sta_iface_5g get_signal`
    if [ "$is_independent_channel_selection_enable" -gt 0 ]; then
        __repacd_wifimon_independent_channel_check $rssi
        if [ "$rssi_num" -gt "$rssi_samples" ]; then
            return 0
        fi
    fi
    # We explicitly ignore clearly bogus values. -95 dBm has been seen in
    # some instances where the STA is not associated by the time the RSSI
    # check is done. The check against 0 tries to guard against scenarios
    # where the firmware has yet to report an RSSI value (although this may
    # never happen if the RSSI gets primed through the association messaging).
    if [ "$rssi" -gt -95 -a "$rssi" -lt 0 ]; then
        if [ "$rssi_num" -lt "$rssi_samples" ]; then
            __repacd_wifimon_debug "RSSI sample #$rssi_num = $rssi dBm"

            # Ignore the very first sample since it is taken at the same time
            # the ping is started (and thus the RSSI might not have been
            # updated).
            if [ "$rssi_num" -eq 0 ]; then
                rssi_filename=`mktemp /tmp/repacd-rssi.XXXXXX`
            else
                # Not the first sample
                echo $rssi >> $rssi_filename
            fi
            rssi_num=$((rssi_num + 1))
        elif [ "$rssi_num" -eq "$rssi_samples" ]; then
            __repacd_wifimon_debug "RSSI sample #$rssi_num = $rssi dBm"

            # We will take one more sample and then draw the conclusion.
            # No further measurements will be taken (although this may be
            # changed in the future).
            echo $rssi >> $rssi_filename

            # We got the required number of samples, now derive the median rssi.
            local rssi_median
            __repacd_wifimon_compute_median $rssi_filename $rssi_num rssi_median
            __repacd_wifimon_info "Median RSSI = $rssi_median dBm"
            measuring_cnt=0
            if [ "$device_type" = 'RE' ]; then
                if [ "$rssi_median" -lt "$rssi_far" ]; then
                    eval "$2=$WIFIMON_STATE_RE_MOVE_CLOSER"
                elif [ "$rssi_median" -gt "$rssi_near" ]; then
                    eval "$2=$WIFIMON_STATE_RE_MOVE_FARTHER"
                else
                    eval "$2=$WIFIMON_STATE_RE_LOCATION_SUITABLE"
                fi

                if [ "$rssi_median" -le "$rssi_pref2G" ] ;then
                    if [ -n "$sta_iface_24g" ] &&
                           __repacd_wifimon_is_assoc $sta_iface_24g ; then
                        __repacd_wifimon_info "Bringing down 5G Due to rssi $rssi_median < rssi_pref2G $rssi_pref2G!"
                        __repacd_wifimon_bring_iface_down $sta_iface_5g
                    fi
                fi
            else  # must be standalone client
                if [ "$rssi_median" -lt "$rssi_min" ]; then
                    eval "$2=$WIFIMON_STATE_CL_LINK_INADEQUATE"
                elif [ "$rssi_median" -gt "$rssi_near" ]; then
                    eval "$2=$WIFIMON_STATE_CL_LINK_SUFFICIENT"
                elif __repacd_wifimon_is_cap_serving; then
                    eval "$2=$WIFIMON_STATE_CL_ACTING_AS_RE"
                else
                    eval "$2=$WIFIMON_STATE_CL_LINK_SUFFICIENT"
                fi
            fi

            rssi_num=$((rssi_num + 1))  # to prevent future samples

            # We have our measurement, so the ping is no longer needed.
            __repacd_stop_ping

            # In case we disassociate after this, we will want to start the
            # association timer again, so clear our state of the last time we
            # started it so that it can be started afresh upon disassociation.
            assoc_start_time=''
        fi
    fi
}

# Determine if a provided amount of time has elapsed.
# input: $1 - start_time: the timestamp (in seconds)
# input: $2 - duration: the amount of time to check against (in seconds)
# return: 0 on timeout; non-zero if no timeout
__repacd_wifimon_is_timeout() {
    local start_time=$1
    local duration=$2

    # Check if the amount of elapsed time exceeds the timeout duration.
    local cur_time
    __repacd_wifimon_get_timestamp cur_time
    local elapsed_time=$(($cur_time - $start_time))
    if [ "$elapsed_time" -gt $duration ]; then
        return 0
    fi

    return 1
}

# Check whether the given interface is the STA interface on the desired
# network and the desired band.
#
# For now, only the 5 GHz band is monitored.
#
# input: $1 - config: the name of the interface config section
# input: $2 - network: the name of the network to which the STA interface
#                      must belong to be matched
# output: $3 - iface: the resolved STA interface name on 2.4 GHz (if found)
# output: $4 - iface_config_name: the resolved name of the config section
#                                 for the STA interface on 2.4 GHz (if found)
# output: $5 - iface: the resolved STA interface name on 5 GHz (if found)
# output: $6 - iface_config_name: the resolved name of the config section
#                                 for the STA interface on 5 GHz (if found)
# output: $7 - unknown_ifaces: whether any Wi-Fi interfaces are as yet
#                              unknown (in terms of their interface name)
__repacd_wifimon_is_sta_iface() {
    local config="$1"
    local network_to_match="$2"
    local iface disabled mode bssid device hwmode

    config_get network "$config" network
    config_get iface "$config" ifname
    config_get disabled "$config" disabled '0'
    config_get mode "$config" mode
    config_get bssid "$config" bssid
    config_get device "$config" device
    config_get hwmode "$device" hwmode

    if [ "$hwmode" != "11ad" ]; then
        if [ "$network" = $network_to_match -a -n "$iface" -a "$mode" = "sta" \
            -a "$disabled" -eq 0 ]; then
            if whc_is_5g_vap $config; then
                eval "$5=$iface"
                eval "$6=$config"
            else
                eval "$3=$iface"
                eval "$4=$config"
            fi
        elif [ -z "$iface" -a "$disabled" -eq 0 ]; then
            # If an interface is showing as enabled but no name is known for it,
            # mark it as such. Without doing this, we can resolve the interface
            # names improperly.
            eval "$7=1"
        fi
    fi
}

# Initialize the sta_iface_5g variable with the STA interface that is enabled
# on the specified network (if any).
# input: $1 - network: the name of the network being managed
__repacd_wifimon_get_sta_iface() {
    unknown_ifaces=0

    config_load wireless
    config_foreach __repacd_wifimon_is_sta_iface wifi-iface $1 \
        sta_iface_24g sta_iface_24g_config_name \
        sta_iface_5g sta_iface_5g_config_name unknown_ifaces

    if [ "$unknown_ifaces" -gt 0 ]; then
        __repacd_wifimon_info " @@ has unknown ifaces, PLZ check wirelss uci cfg! clear out all sta_ifaces vars "
        # Clear out everything because we cannot be certain we have the
        # right names (eg. interfaces may not all be up yet).
        sta_iface_24g=
        sta_iface_24g_config_name=
        sta_iface_5g=
        sta_iface_5g_config_name=
    fi
}

# Check whether the given interface is the AP interface on the desired
# network and the desired band.
#
# For now, only the 5 GHz band is monitored.
#
# input: $1 - config: the name of the interface config section
# input: $2 - network: the name of the network to which the AP interface
#                      must belong to be matched
# output: $3 - iface: the resolved AP interface name on 2.4 GHz (if found)
# output: $4 - iface_config_name: the resolved name of the config section
#                                 for the AP interface on 2.4 GHz (if found)
# output: $5 - iface: the resolved AP interface name on 5 GHz (if found)
# output: $6 - iface_config_name: the resolved name of the config section
#                                 for the AP interface on 5 GHz (if found)
# output: $7 - unknown_ifaces: whether any Wi-Fi interfaces are as yet
#                              unknown (in terms of their interface name)
__repacd_wifimon_is_ap_iface() {
    local config="$1"
    local network_to_match="$2"
    local iface disabled mode bssid device hwmode

    config_get network "$config" network
    config_get iface "$config" ifname
    config_get disabled "$config" disabled '0'
    config_get mode "$config" mode
    config_get bssid "$config" bssid
    config_get device "$config" device
    config_get hwmode "$device" hwmode

    if [ "$hwmode" != "11ad" ]; then
        if [ "$network" = $network_to_match -a -n "$iface" -a "$mode" = "ap" \
            -a "$disabled" -eq 0 ]; then
            if whc_is_5g_vap $config; then
                eval "$5=$iface"
                eval "$6=$config"
            else
                eval "$3=$iface"
                eval "$4=$config"
            fi
        elif [ -z "$iface" -a "$disabled" -eq 0 ]; then
            # If an interface is showing as enabled but no name is known for it,
            # mark it as such. Without doing this, we can resolve the interface
            # names improperly.
            eval "$7=1"
        fi
    fi
}

# Initialize the sta_iface_5g variable with the AP interface that is enabled
# on the specified network (if any).
# input: $1 - network: the name of the network being managed
__repacd_wifimon_get_ap_iface() {
    unknown_ifaces=0

    config_load wireless
    config_foreach __repacd_wifimon_is_ap_iface wifi-iface $1 \
        ap_iface_24g ap_iface_24g_config_name \
        ap_iface_5g ap_iface_5g_config_name unknown_ifaces

    if [ "$unknown_ifaces" -gt 0 ]; then
        # Clear out everything because we cannot be certain we have the
        # right names (eg. interfaces may not all be up yet).
        ap_iface_24g=
        ap_iface_24g_config_name=
        ap_iface_5g=
        ap_iface_5g_config_name=
    fi
}

# Back haul  monitoring logic : in case 5G was brought down
# forcefully due to RSSI constraints and 2.4 G also went down
# and stayed of for more then 2GBackhaulSwitchDownTime sec
# bring back 5G.
# input: $1 - re_mode: Current RE mode we are operating in.
# input: $2 - re_submode: Current RE sub-mode we are operating in.
# output:None

__repacd_wifimon_evaluate_backhaul_link() {
    local re_mode=$1
    local re_submode=$2

    if [ "$force_down_5g" -gt 0 ] ; then
        if  ! __repacd_wifimon_is_assoc $sta_iface_24g;then
            if [ -z "$down_time_2g" ]; then
                __repacd_wifimon_get_timestamp down_time_2g
            fi

            if __repacd_wifimon_is_timeout $down_time_2g $config_downtime2G; then
                __repacd_wifimon_info "Bringing up 5G: 2G backhaul went down"
                __repacd_wifimon_bring_iface_up $sta_iface_5g
                __repacd_wifimon_get_timestamp assoc_start_time
                down_time_2g=''
                badlink_switch_inprogress=0
            fi
        else
            down_time_2g=''
        fi

        if  __repacd_wifimon_is_timeout $force_down_5g_timestamp $backhaul_eval_time; then
            __repacd_wifimon_info "Bringing up 5G:eval interval $backhaul_eval_time sec expired"
            __repacd_wifimon_bring_iface_up $sta_iface_5g
            __repacd_wifimon_get_timestamp force_down_5g_timestamp
            __repacd_wifimon_get_timestamp assoc_start_time
        fi
    elif [ "$force_down_24g" -gt 0 ]; then
        # If we are associated to CAP and 2.4G was brought down due to badlink,
        # Try enabling 2.4G after specified timeout.
        if [ "$last_assoc_state" -gt 0 ] \
            && __repacd_wifimon_is_assoc $sta_iface_5g; then
            if [ -z "$down_time_2g" ]; then
                __repacd_wifimon_get_timestamp down_time_2g
            fi

            if __repacd_wifimon_is_timeout $down_time_2g $config_eval_time24g; then
                if [ "$backhaul_mode_configured" = "$backhaul_mode_single" ] && __repacd_wifimon_is_active_assoc $sta_iface_5g && ! __repacd_wifimon_is_active_assoc $sta_iface_24g; then
                    return
                fi
                __repacd_wifimon_info "Bringing up 2.4G: Trying to associate"
                __repacd_wifimon_bring_iface_up $sta_iface_24g
                down_time_2g=''
            fi
        else
            down_time_2g=''
        fi
    fi
}

# Get phyrate in mbps
# input: $1 - 'interface on which phyrate is to be calculated'
# output: $2 - current maximum phyrate possible in Mbps
__repacd_wifimon_get_current_phyrate_in_mbps() {
    local  measurement_iface=$1
    local phyrate_in_mbps
    local phyrate_unit
    local padding="00000"

    # Get the phyrate and rate units of the interface.
#    eval $(iwconfig $measurement_iface |grep 'Bit Rate' | awk -F':' '{print $2}' | awk '{ \
#       a = $1;b = $2} END{print "phyrate_in_mbps=\""a"\"; \
#       phyrate_unit=\""b"\""}')
    eval $(repacdcli $measurement_iface get_bitrate_unit | awk '{ a = $1;b = $2} \
            END{print "phyrate_in_mbps=\""a"\"; phyrate_unit=\""b"\""}')
    # If the phyrate is in Gbps, then convert it to Mbps
    if [ $phyrate_unit = "Gb/s" ]; then
       phyrate_in_mbps=$(echo $phyrate_in_mbps${padding:${#phyrate_in_mbps}} | sed 's/\.//g' | cut -c1-4)
    else
       phyrate_in_mbps=$(echo "$phyrate_in_mbps" | sed 's/\.//g' | cut -c1-3)
    fi

    eval "$2=$phyrate_in_mbps"
}


# Set rate measurement interface on which rate measurement
# is to be done.
# input: $1 - '5g' or '24g'
__repacd_wifimon_set_rate_measurement_iface() {
    local measurement_sta_iface_rate

    if [ "$1" = '5g' ]; then
        measurement_sta_iface=$sta_iface_5g
        measurement_sta_iface_config_name=$sta_iface_5g_config_name
    elif [ "$1" = '24g' ]; then
        measurement_sta_iface=$sta_iface_24g
        measurement_sta_iface_config_name=$sta_iface_24g_config_name
    fi

    # Not associated, we will not get valid rate, return
    if [ "$force_down_5g" -gt 0 ] \
        || ! __repacd_wifimon_is_assoc $sta_iface_5g; then
        return
    fi

    # Get the phyrate of the measurement sta interface.
    __repacd_wifimon_get_current_phyrate_in_mbps $measurement_sta_iface measurement_sta_iface_rate
    __repacd_wifimon_debug "Current maxrate is $measurement_sta_iface_rate"

    # Update the state variables depending upon the phyrate
    # of the associated sta interface. (Currently 5G)
    rate_min=$(($percent_rate_min5G*${measurement_sta_iface_rate}/100))
    rate_max=$(($percent_rate_max5G*${measurement_sta_iface_rate}/100))
    rate_pref2G=$(($percent_rate_pref2G*${measurement_sta_iface_rate}/100))

    MoveFromCAP_snr_threshold=$(($CAP_snr_threshold-$MoveFromCAP_snr_hysteresis))

    __repacd_wifimon_debug "Rate thresholds Min=$rate_min Max=$rate_max Pref2G=$rate_pref2G"
    __repacd_wifimon_debug "SNR thresholds CAP attach=$CAP_snr_threshold db CAP detach=$MoveFromCAP_snr_threshold db"
}

# Check for configured BSSID in wireless file and update if required.
# Driver will arrive at the best AP based on rate and return the BSSID,
# the BSSID is written to the wireless config file using UCI.
# input: $1 - sta_iface: sta interface to configure
# input: $2 - sta_iface_config_name: config name of the sta interface
# input: $3 - new_bssid: BSSID value to configure
# output: $4 - restart wifi required or not
# output: $5 - Configuration changed
__repacd_wifimon_check_and_config_bssid() {
    local sta_iface=$1
    local sta_iface_config_name=$2
    local new_bssid=$3
    local current_bssid peer_bssid

    eval "$4=0"
    eval "$5=0"

    # If BSSID is empty, return
    if [ -z "$new_bssid" ]; then
        return
    fi

#    current_bssid=`iwconfig $sta_iface | grep "Access Point" | awk -F" " '{print $6}'`
    current_bssid=`repacdcli $sta_iface get_sta_link`

    config_load wireless
    # If supplied BSSID and configured BSSID are same, simply return.
    if __repacd_wifimon_is_peer_bssid_set $sta_iface_config_name; then
        if [ "$new_bssid" = "$peer_bssid" ]; then
            __repacd_wifimon_debug "$sta_iface: BSSID up to date"
            return
        fi
    elif [ "$new_bssid" = "$current_bssid" ]; then
        # Associated BSSID and supplied BSSID are same, just update
        # the config file, no restart required.
        uci_set wireless $sta_iface_config_name bssid $new_bssid
        uci_commit wireless
        __repacd_wifimon_info "$sta_iface: BSSID updated to $new_bssid, NO RESTART required"
        eval "$5=1"
        return
    fi

    # Write the new BSSID to wireless config file
    uci_set wireless $sta_iface_config_name bssid $new_bssid
    uci_commit wireless
    eval "$5=1"
    eval "$4=1"
    __repacd_wifimon_info "$sta_iface: BSSID updated to $new_bssid, RESTART required"
}

# Configure BSSID via wpa_cli interface of given sta interface
# and restart interface if requested.
# input: $1 - sta_iface: sta interface to configure
# input: $2 - new_bssid: BSSID value to configure
# output: $3 - restart wifi required or not
# If AP is operating in single backhaul mode configure the bssid
# for 2g but dont enable the interface
__repacd_wifimon_wpa_config_bssid() {
    local sta_iface=$1
    local new_bssid=$2
    local restart=$3

    if [ -n "$sta_iface" ]; then
        if [ "$restart" -gt 0 ]; then
            # Restart the network with configured BSSID
            # miwifi xqwhc lock protect ops from xqwhc backhaul superv
            __repacd_wifimon_info "Bringing down/up $sta_iface due to bssid config & restart!"
             xqwhc_repacd_sync_lock lock $sta_iface
            wpa_cli -p /var/run/wpa_supplicant-$sta_iface disable_network 0
            wpa_cli -p /var/run/wpa_supplicant-$sta_iface set_network 0 bssid $new_bssid
            wpa_cli -p /var/run/wpa_supplicant-$sta_iface enable_network 0
             xqwhc_repacd_sync "${XQWHC_REPACD_IFDOWN}_${sta_iface}" 0
             xqwhc_repacd_sync_lock unlock $sta_iface
        else
            # Just configure the BSSID
            wpa_cli -p /var/run/wpa_supplicant-$sta_iface set_network 0 bssid $new_bssid
        fi
    fi
}

# Get current best AP based on Rate estimate.
# Driver will arrive at the best AP based on rate and return the BSSIDs.
# Best AP is determined on provided STA interface which will
# also return otherband BSSID of the same device (i.e. Best uplink node).
# input:  $1 - sta_iface - STA interface to get best uplink BSSID
# output: $2 - bestap BSSID
# output: $3 - bestap otherband BSSID
__repacd_wifimon_get_current_best_ap() {
    local sta_iface=$1
    local best_bssid best_otherband_bssid


    # Driver returns BSSID without separator(:), add the separator before writting
    # to config file.
    # Send ioctl request to send bcast probe req with configured ssid to discover
    # neighbor backhaul APs with hidden ssids. The initial reading may not contain
    # the updated bssid list as newly discovered bssid(s) may not be a part of scan
    # result. Subsequent reading should get updated scan list as reading is done
    # every 2secs.
    if [ -z $REPACD_CFG80211 ]; then
        iwpriv $sta_iface sendprobereq 1
        best_bssid=`iwpriv $sta_iface get_whc_bssid | awk -F":" '{print $2}' | \
            sed -e "s/\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)/\1:\2:\3:\4:\5:\6/"`
        best_otherband_bssid=`iwpriv $sta_iface g_best_ob_bssid | awk -F":" '{print $2}' | \
            sed -e "s/\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)/\1:\2:\3:\4:\5:\6/"`
    else
        cfg80211tool $sta_iface sendprobereq 1
        best_bssid=`cfg80211tool $sta_iface get_whc_bssid | awk -F":" '{print $2}' | \
            sed -e "s/\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)/\1:\2:\3:\4:\5:\6/"`
        best_otherband_bssid=`cfg80211tool $sta_iface g_best_ob_bssid | awk -F":" '{print $2}' | \
            sed -e "s/\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)/\1:\2:\3:\4:\5:\6/"`
    fi

    eval "$2=$best_bssid"
    eval "$3=$best_otherband_bssid"
}

# Configure Best AP based on Rate for given sta interface
# Driver will arrive at the best AP based on rate and return the BSSID,
# the BSSID is written to the wireless config file using UCI.
# input: $1 - sta_iface - station interface to configure best BSSID
# input: $2 - sta_iface_config_name - station interface config name
# output: $3 - VAP restart done or not
# output: $4 - BSSID configuration status 1 - success & 0 - failed
__repacd_wifimon_config_best_ap() {
    local sta_iface=$1
    local sta_iface_config_name=$2
    local otherband_sta_iface otherband_sta_iface_config_name
    local selected_bssid peer_bssid
    local sta1_config_changed=0 sta2_config_changed=0
    local config_status=0 sta1_restart=0 sta2_restart=0

    eval "$3=0"

    if [ -n "$sta_iface" ]; then
       __repacd_wifimon_debug "$sta_iface: Configure Best AP"

       if [ "$sta_iface" = "$sta_iface_5g" ]; then
           otherband_sta_iface=$sta_iface_24g
           otherband_sta_iface_config_name=$sta_iface_24g_config_name
       else
           otherband_sta_iface=$sta_iface_5g
           otherband_sta_iface_config_name=$sta_iface_5g_config_name
       fi
       if [ -n "$new_bestap" -a "$new_bestap" != "00:00:00:00:00:00" ]; then
           if [ -n "$otherband_sta_iface" -a -n "$new_bestap_otherband" \
               -a "$new_bestap_otherband" != "00:00:00:00:00:00" ] \
               || [ -z "$otherband_sta_iface" ]; then
               __repacd_wifimon_debug "Best AP = $new_bestap"
               __repacd_wifimon_check_and_config_bssid $sta_iface \
                   $sta_iface_config_name $new_bestap sta1_restart sta1_config_changed
               if [ "$sta1_restart" -gt 0 ]; then
                    xqwhc_repacd_sync_lock lock $sta_iface
                    __repacd_wifimon_info "Bringing down $sta_iface due to bssid update! [$sta1_restart][$sta1_config_changed] "
                   wpa_cli -p /var/run/wpa_supplicant-$sta_iface disable_network 0
                    xqwhc_repacd_sync "${XQWHC_REPACD_IFDOWN}_${sta_iface}" 1
                    xqwhc_repacd_sync_lock unlock $sta_iface
               fi

               # Configure the otherband BSSID also.
               if [ -n "$otherband_sta_iface" ]; then
                   __repacd_wifimon_debug "Best AP otherband = $new_bestap_otherband"
                   __repacd_wifimon_check_and_config_bssid $otherband_sta_iface \
                       $otherband_sta_iface_config_name $new_bestap_otherband sta2_restart sta2_config_changed
                   if [ "$sta2_restart" -gt 0 ]; then
                       __repacd_wifimon_info "Bringing down $otherband_sta_iface due to bssid update! [$sta2_restart][$sta2_config_changed]"
                       xqwhc_repacd_sync_lock lock $otherband_sta_iface
                       wpa_cli -p /var/run/wpa_supplicant-$otherband_sta_iface disable_network 0
                       xqwhc_repacd_sync "${XQWHC_REPACD_IFDOWN}_${otherband_sta_iface}" 1
                       xqwhc_repacd_sync_lock unlock $otherband_sta_iface
                   fi
               fi

               # Enable disabled VAPs now, so that both bands connect to the same node.
               if [ "$sta1_config_changed" -gt 0 ]; then
                   __repacd_wifimon_wpa_config_bssid $sta_iface $new_bestap 0
                   if [ "$sta1_restart" -gt 0 ]; then
                       __repacd_wifimon_info "Bringing up $sta_iface due to bssid update & restart need! [$sta1_restart][$sta1_config_changed]"
                       xqwhc_repacd_sync_lock lock $sta_iface
                       wpa_cli -p /var/run/wpa_supplicant-$sta_iface enable_network 0
                       xqwhc_repacd_sync "${XQWHC_REPACD_IFDOWN}_${sta_iface}" 0
                       xqwhc_repacd_sync_lock unlock $sta_iface
                   fi
               fi
               if [ "$sta2_config_changed" -gt 0 ]; then
                   __repacd_wifimon_wpa_config_bssid $otherband_sta_iface $new_bestap_otherband 0
                   if [ "$sta2_restart" -gt 0 ]; then
                       __repacd_wifimon_info "Bringing up $otherband_sta_iface due to bssid update & restart need! [$sta2_restart][$sta2_config_changed]"
                       xqwhc_repacd_sync_lock lock $otherband_sta_iface
                       wpa_cli -p /var/run/wpa_supplicant-$otherband_sta_iface enable_network 0
                       xqwhc_repacd_sync "${XQWHC_REPACD_IFDOWN}_${otherband_sta_iface}" 0
                       xqwhc_repacd_sync_lock unlock $otherband_sta_iface
                   fi
               fi

               eval "$3=$((sta1_restart + sta2_restart))"
               config_status=1
           fi
       else
           config_status=0
           __repacd_wifimon_debug "No valid Best AP found"
       fi
    fi

    eval "$4=$config_status"
}

# Configure BSSID of Current association to the provided sta interface.
# The BSSID is arrived from iwconfig command.
# The BSSID is written to the wireless config file using UCI.
# input: $1 - sta_iface: station interface to configure current BSSID
# input: $2 - sta_iface_config_name: station interface config name
__repacd_wifimon_config_current_bssid() {
    local sta_iface=$1
    local sta_iface_config_name=$2
    local selected_bssid restart=0 config_changed=0

    if [ -n "$sta_iface" ]; then
        # Get the currently associated BSSID from iwconfig.
#        selected_bssid=`iwconfig $sta_iface | grep "Access Point" | awk -F" " '{print $6}'`
        selected_bssid=`repacdcli $sta_iface get_sta_link`
        __repacd_wifimon_debug "$sta_iface: BSSID = $selected_bssid"

        if [ -n "$selected_bssid" -a "$selected_bssid" != "00:00:00:00:00:00" ]; then
            __repacd_wifimon_check_and_config_bssid $sta_iface \
                $sta_iface_config_name $selected_bssid restart config_changed
        fi
        # Restart the network with configured BSSID, if required.
        if [ "$config_changed" -gt 0 ]; then
            __repacd_wifimon_wpa_config_bssid $sta_iface $selected_bssid $restart
        fi
    fi
}

# Configure 2.4G BSSID of CAP for the provided sta interface.
# Driver will arrive at the CAP 2.4G BSSID,
# the BSSID is written to the wireless config file using UCI.
# input: None
__repacd_wifimon_config_cap_24g_bssid() {
    local selected_bssid restart=0 config_changed=0

    if [ -n "$sta_iface_24g" ]; then
        # Driver returns BSSID without separator(:), add the separator before writting
        # to config file.
        if [ -z $REPACD_CFG80211 ]; then
            selected_bssid=`iwpriv $sta_iface_24g g_whc_cap_bssid | awk -F":" '{print $2}' | \
            sed -e "s/\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)/\1:\2:\3:\4:\5:\6/"`
        else
            selected_bssid=`cfg80211tool $sta_iface_24g g_whc_cap_bssid | awk -F":" '{print $2}' | \
            sed -e "s/\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)/\1:\2:\3:\4:\5:\6/"`
        fi
        __repacd_wifimon_debug "$sta_iface_24g: CAP BSSID = $selected_bssid"

        if [ -n "$selected_bssid" -a "$selected_bssid" != "00:00:00:00:00:00" ]; then
            __repacd_wifimon_check_and_config_bssid $sta_iface_24g \
                $sta_iface_24g_config_name $selected_bssid restart config_changed
        fi
        if [ "$restart" -gt 0 ]; then
            # Restart the network with configured BSSID
            __repacd_wifimon_wpa_config_bssid $sta_iface_24g $selected_bssid $restart
        elif [ "$config_changed" -gt 0 ]; then
            __repacd_wifimon_wpa_config_bssid $sta_iface_24g $selected_bssid $restart
        fi
    fi
}

# Configure BSSID for the disabled sta interface.
# Driver will arrive at the otherband BSSIDs from provided STA interface,
# the BSSID is written to the wireless config file using UCI and update the network.
# input: $1 - sta_iface: station interface on which otherband BSSIDs to be found
__repacd_wifimon_find_and_config_otherband_bssid() {
    local selected_bssid restart=0 config_changed=0
    local otherband_sta_iface otherband_sta_iface_config_name
    local sta_iface=$1

    if [ -n "$sta_iface" ]; then
        if [ "$sta_iface" = "$sta_iface_5g" ]; then
            otherband_sta_iface=$sta_iface_24g
            otherband_sta_iface_config_name=$sta_iface_24g_config_name
        else
            otherband_sta_iface=$sta_iface_5g
            otherband_sta_iface_config_name=$sta_iface_5g_config_name
        fi
        if [ -n "$otherband_sta_iface" -a -n "$otherband_sta_iface_config_name" ]; then
            # Driver returns BSSID without separator(:), add the separator before writting
            # to config file.
            if [ -z $REPACD_CFG80211 ]; then
                selected_bssid=`iwpriv $sta_iface g_whc_ob_bssid | awk -F":" '{print $2}' | \
                sed -e "s/\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)/\1:\2:\3:\4:\5:\6/"`
            else
                selected_bssid=`cfg80211tool $sta_iface g_whc_ob_bssid | awk -F":" '{print $2}' | \
                sed -e "s/\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)/\1:\2:\3:\4:\5:\6/"`
            fi
            __repacd_wifimon_debug "OtherBand BSSID = $selected_bssid"

            if [ -n "$selected_bssid" -a "$selected_bssid" != "00:00:00:00:00:00" ]; then
                __repacd_wifimon_check_and_config_bssid $otherband_sta_iface \
                    $otherband_sta_iface_config_name $selected_bssid restart config_changed
            fi
            # Restart the network with configured BSSID, if required.
            if [ "$config_changed" -gt 0 ]; then
                __repacd_wifimon_wpa_config_bssid $otherband_sta_iface $selected_bssid $restart
            fi
        fi
    fi
}

# Initialize the Wi-Fi monitoring logic with the name of the network being
# monitored.
# input: $1 - network: the name of the network being managed
# input: $2 - cur_re_mode: the current operating range extender mode
# input: $3 - cur_re_submode: the current operating range extender submode
# input: $4 - autoconfig: whether it was an auto-config restart
# output: $5 - state: the name of the initial state
# output: $6 - new_re_mode: the resolved range extender mode
# output: $7 - new_re_submode: the resolved range extender submode
repacd_wifimon_init() {
    # Resolve the STA interfaces.
    # Here we assume that if we have the 5 GHz interface, that is sufficient,
    # as not all modes will have a 2.4 GHz interface.
    # Loading Forwading mode to see if AP is operating in APS or Single backhaul mode
    config_load hyd
    config_get backhaul_mode_configured 'hy' 'ForwardingMode' 'APS'
    __repacd_wifimon_debug "Backhaul mode is $backhaul_mode_configured"
    __repacd_wifimon_get_ap_iface $1

    if [ -n "$ap_iface_24g" ]; then
        __repacd_wifimon_debug "Resolved 2.4 GHz AP interface to $ap_iface_24g"
        __repacd_wifimon_debug "2.4 GHz AP interface section $ap_iface_24g_config_name"
    fi

    if [ -n "$ap_iface_5g" ]; then
        __repacd_wifimon_debug "Resolved 5 GHz AP interface to $ap_iface_5g"
        __repacd_wifimon_debug "5 GHz AP interface section $ap_iface_5g_config_name"
    fi

    __repacd_wifimon_get_sta_iface $1
    #__repacd_wifimon_debug " @@ sta ifaces: $sta_iface_5g, $sta_iface_24g "

    if [ -n "$sta_iface_5g" -o -n "$sta_iface_24g" ]; then
        local re_mode=$2
        local re_submode=$3

        if [ -n "$sta_iface_24g" ]; then
            __repacd_wifimon_debug "Resolved 2.4 GHz STA interface to $sta_iface_24g"
            __repacd_wifimon_debug "2.4 GHz STA interface section $sta_iface_24g_config_name"
        fi

        if [ -n "$sta_iface_5g" ]; then
            __repacd_wifimon_debug "Resolved 5 GHz STA interface to $sta_iface_5g"
            __repacd_wifimon_debug "5 GHz STA interface section $sta_iface_5g_config_name"
        fi
        # First resolve the config parameters.
        config_load repacd
        config_get device_type 'repacd' 'DeviceType' 'RE'
        config_get config_re_mode 'repacd' 'ConfigREMode' 'auto'
        config_get default_re_mode 'repacd' 'DefaultREMode' 'qwrap'
        config_get traffic_separation_enabled repacd TrafficSeparationEnabled '0'
        config_get traffic_separation_active repacd TrafficSeparationActive '0'
        config_get guest_backhaul repacd NetworkGuestBackhaulInterface 'both'
        config_get network_guest repacd NetworkGuest 'guest'

        config_get min_auto_mode_assoc 'WiFiLink' 'MinAssocCheckAutoMode' '5'
        config_get min_wps_assoc 'WiFiLink' 'MinAssocCheckPostWPS' '5'
        config_get min_bssid_assoc 'WiFiLink' 'MinAssocCheckPostBSSIDConfig' '5'
        config_get wps_timeout 'WiFiLink' 'WPSTimeout' '120'
        config_get assoc_timeout 'WiFiLink' 'AssociationTimeout' '300'
        config_get rssi_samples 'WiFiLink' 'RSSINumMeasurements' '5'
        config_get rssi_far 'WiFiLink' 'RSSIThresholdFar' '-75'
        config_get rssi_near 'WiFiLink' 'RSSIThresholdNear' '-60'
        config_get rssi_min 'WiFiLink' 'RSSIThresholdMin' '-75'
        config_get rssi_pref2G 'WiFiLink' 'RSSIThresholdPrefer2GBackhaul' '-120'
        config_get snr_pref2G  'WiFiLink' 'SNRThresholdPrefer2GBackhaul' '5'
        config_get snr_enabled 'WiFiLink' 'EnableSNRBasedPrefer2GBackhaul' '1'
        config_get config_downtime2G 'WiFiLink' '2GBackhaulSwitchDownTime' '10'
        config_get measuring_attempts 'WiFiLink' 'MaxMeasuringStateAttempts' '3'
        config_get daisy_chain 'WiFiLink' 'DaisyChain' '0'
        config_get rate_samples 'WiFiLink' 'RateNumMeasurements' '5'
        config_get percent_rate_min5G 'WiFiLink' 'RateThresholdMin5GInPercent' '40'
        config_get percent_rate_max5G 'WiFiLink' 'RateThresholdMax5GInPercent' '70'
        config_get percent_rate_pref2G 'WiFiLink' 'RateThresholdPrefer2GBackhaulInPercent' '5'
        config_get bssid_assoc_timeout 'WiFiLink' 'BSSIDAssociationTimeout' '90'
        config_get badlink_timeout5G 'WiFiLink' '5GBackhaulBadlinkTimeout' '60'
        config_get config_short_eval_time5g 'WiFiLink' '5GBackhaulEvalTimeShort' '1800'
        config_get config_long_eval_time5g  'WiFiLink' '5GBackhaulEvalTimeLong' '7200'
        config_get config_eval_time24g 'WiFiLink' '2GBackhaulEvalTime' '1800'
        config_get is_independent_channel_selection_enable 'WiFiLink' '2GIndependentChannelSelectionEnable' '0'
        config_get quality_5g_rssi_level 'WiFiLink' '2GIndependentChannelSelectionRssiLevel' '-70'
        config_get rssi_check_total_counter 'WiFiLink' '2GIndependentChannelSelectionTotalRssiCounter' '10'
        config_get rssi_idle_time 'WiFiLink' '2GIndependentChannelSelectionStartRssiCheckTime' '60'
        config_get CAP_snr_threshold 'WiFiLink' 'PreferCAPSNRThreshold5G' '0'
        config_get MoveFromCAP_snr_hysteresis 'WiFiLink' 'MoveFromCAPSNRHysteresis5G' '3'

        # Find the 2.4G wifi interface and set independent_channel_set to defalut value zero to avoid
        # if device re-power on without unknow reason to keep it as 1.
        uci show wireless | grep 11ng | sed 's/.hwmode.*//g' | sed 's/wireless.//g' > /tmp/wifi_2G_interface.txt
        exec < '/tmp/wifi_2G_interface.txt'
        while read line
        do
            __repacd_wifimon_debug $line
            wifi_2G_interface_name=$line
            uci_set wireless $wifi_2G_interface_name independent_channel_set '0'
            uci_commit wireless
        done
        rm -rf /tmp/wifi_2G_interface.txt

        # Create ourselves a named pipe so we can be informed of WPS push
        # button events.
        if [ -e $WIFIMON_PIPE_NAME ]; then
            rm -f $WIFIMON_PIPE_NAME
        fi

        mkfifo $WIFIMON_PIPE_NAME

        # For fresh boot of RE we avoid supplicant not to choose the node
        # This check was to initialise best uplink before bssid assoc time for reboot or restart
        if __repacd_wifimon_is_peer_bssid_invalid $sta_iface_5g_config_name && __repacd_wifimon_is_peer_bssid_invalid $sta_iface_24g_config_name; then
        local assoc_retry=7
            while [ "$assoc_retry" -gt 0 ]; do
                __repacd_wifimon_debug "BSSID was set to invalid since RE rebooted or repacd restarted. Running best uplink "
                __repacd_wifimon_get_current_best_ap $sta_iface_5g new_bestap new_bestap_otherband
                __repacd_wifimon_config_best_ap $sta_iface_5g $sta_iface_5g_config_name restarted config_success
                sleep 5
                if ! __repacd_wifimon_is_assoc $sta_iface_5g; then
                    assoc_retry=$((assoc_retry -1))
                    sleep 10
                else
                    break
                fi
            done
        fi

        # If already associated, go to the InProgress state.
        __repacd_wifimon_check_associated $1 $2 $3 $4 $5 $6 $7
    fi
    # Otherwise, must be operating in CAP mode.
}

# Check the status of the Wi-Fi link (WPS, association, and RSSI).
# input: $1 - network: the name of the network being managed
# input: $2 - cur_re_mode: the currently configured range extender mode
# input: $3 - cur_re_submode: the currently configured range extender sub-mode
# output: $4 - state: the name of the new state (only set upon a change)
# output: $5 - re_mode: the desired range extender mode (updated only once
#                       the link to the AP is considered stable)
# output: $6 - re_submode: the desired range extender submode (updated only once
#                       the link to the AP is considered stable)
repacd_wifimon_check() {
    if [ -n "$sta_iface_5g" ]; then
        local new_root_distance

        # Make sure all the AP interfaces are broadcasting right hop count.
        # If required, inherit the root distance from active station interface.
        __repacd_get_min_root_ap_dist new_root_distance

        if [ "$new_root_distance" != "$curr_root_distance" ]; then
            __repacd_wifimon_debug "Root AP distance: $new_root_distance"

            config_load wireless
            config_foreach __repacd_wifimon_set_root_distance wifi-iface $new_root_distance
            curr_root_distance=$new_root_distance

            if [ "$new_root_distance" -eq $RE_ROOT_AP_DISTANCE_INVALID ]; then
                __repacd_wifimon_set_uplink_rate $sta_iface_5g 0
                __repacd_wifimon_set_uplink_rate $sta_iface_24g 0
            fi
        fi

        # We depend on 5G interface for measuring rate, if forced down,
        # copy the rate from 2.4G interface.
        if [ "$force_down_5g" -gt 0 ]; then
            __repacd_wifimon_copy_uplink_rate $sta_iface_24g $sta_iface_5g
        fi

        if __repacd_wifimon_check_associated $1 $2 $3 0 $4 $5 $6; then
            assoc_timeout_logged=0
            wps_timeout_logged=0
        else  # not associated
            # Check if the WPS button was pressed.
            local wps_pbc
            read -t 1 wps_pbc <>$WIFIMON_PIPE_NAME
            if [ $? -eq 0 ]; then
                eval "$4=$WIFIMON_STATE_AUTOCONFIG_IN_PROGRESS"
                wps_in_progress=1
                __repacd_wifimon_get_timestamp wps_start_time

                # Forcefully delete the BSSID from the STA interface in case
                # the new AP does not support IEEE1905.1+QCA extensions deep
                # cloning.
                __repacd_wifimon_debug "Delete BSSID for $sta_iface_5g"
                uci delete wireless.${sta_iface_5g_config_name}.bssid

                if [ -n "$sta_iface_24g" ]; then
                    __repacd_wifimon_debug "Delete BSSID for $sta_iface_24g"
                    uci delete wireless.${sta_iface_24g_config_name}.bssid
                fi

                uci commit wireless

                # Do not check the association timeout below.
                return 0
            fi

            if [ "$wps_in_progress" -gt 0 ]; then
                if __repacd_wifimon_is_timeout $wps_start_time $wps_timeout; then
                    if [ "$wps_timeout_logged" -eq 0 ]; then
                        __repacd_wifimon_debug "WPS timeout"
                        wps_timeout_logged=1
                    fi

                    eval "$4=$WIFIMON_STATE_WPS_TIMEOUT"
                fi
            else
                # if 2.4G inteface is down by independent channel selection
                # and 5G itnerface is gone, wake up the 2.4G interface
                if [ "$is_independent_channel_selection_enable" -gt 0 ]; then
                    if [ "$is_24G_down_by_independent_channel" -gt 0 ]; then
                        if __repacd_wifimon_is_assoc $sta_iface_5g; then
                           __repacd_wifimon_info "5G still alive"
                        else
                            __repacd_wifimon_info " is_24G_down_by_independent_channel, up sta_iface_24g"
                            __repacd_wifimon_bring_iface_up $sta_iface_24g
                            return 0
                        fi
                    fi
                fi
                if [ "$daisy_chain" -gt 0 ]; then
                    if __repacd_wifimon_is_timeout $assoc_start_time $bssid_assoc_timeout; then
                        local reset_bssid=0
                        local restarted=0 config_success=0

                        config_load wireless
                        # If one backhaul link is associated and other one is not associated,
                        # bring down non associated backhaul and proceed to link measurement.
                        if [ -n "$sta_iface_24g" ] && [ -n "$sta_iface_5g" ]; then
                            if [ "$force_down_24g" -eq 0 -a "$force_down_5g" -eq 0 ]; then
                                if __repacd_wifimon_is_assoc $sta_iface_5g; then
                                    # Ignore 2.4G backhaul association check,
                                    # we are not associated for long time.
                                    # 5G backhaul is ready to take over.
                                    __repacd_wifimon_debug "BSSID Assoc timeout: Ignoring 2.4G Association check"
                                    __repacd_wifimon_get_timestamp assoc_start_time
                                    ignore_24g_assoc=1
                                elif __repacd_wifimon_is_assoc $sta_iface_24g; then
                                    # Before bringing down 5G backhaul try finding best AP,
                                    # still if no best AP found bringdown 5G backhaul.
                                    if __repacd_wifimon_is_peer_bssid_set $sta_iface_5g_config_name; then
                                        __repacd_wifimon_debug "BSSID Assoc timeout: 5G not associated"
                                        __repacd_wifimon_get_current_best_ap $sta_iface_5g new_bestap new_bestap_otherband
                                        __repacd_wifimon_config_best_ap $sta_iface_5g $sta_iface_5g_config_name restarted config_success
                                        if [ "$config_success" -gt 0 ]; then
                                            __repacd_wifimon_get_timestamp assoc_start_time
                                            eval "$4=$WIFIMON_STATE_BSSID_ASSOC_TIMEOUT"
                                            return
                                        fi
                                    fi
                                    # Bring down 5G backhaul, we are not associated for long time.
                                    # 2.4G backhaul is ready to take over.
                                    __repacd_wifimon_info "BSSID Assoc timeout: bringing down 5G"
                                    __repacd_wifimon_bring_iface_down $sta_iface_5g
                                    __repacd_wifimon_get_timestamp assoc_start_time
                                else
                                    # Both the backhaul links are not associated, try resetting BSSID.
                                    __repacd_wifimon_info "BSSID Assoc timeout: both 5G and 2.4G not associated"
                                    reset_bssid=1
                                fi
                            else
                                # We are already operating in single link,
                                # try resetting BSSID in APS mode and enabling
                                # 2g in case of SINGLE mode.
                                __repacd_wifimon_info "BSSID Assoc timeout: already in single link, not associated"
                                if [ "$backhaul_mode_configured" = "$backhaul_mode_single" ] && \
                                    ! __repacd_wifimon_is_active_assoc $sta_iface_5g && ! __repacd_wifimon_is_active_assoc $sta_iface_24g; then
                                    __repacd_wifimon_info "Enabling 2g as failsafe"
                                    __repacd_wifimon_bring_iface_up $sta_iface_24g
                                fi

                                reset_bssid=1
                            fi
                        else
                            __repacd_wifimon_info "BSSID Assoc timeout: try clearing BSSID, if any"
                            reset_bssid=1
                        fi

                        if [ "$reset_bssid" -gt 0 ]; then
                            # Configured BSSID association timed out,
                            # the desired BSSID might have powered down or not reachable.
                            # Try running Best AP selection to find an AP.
                            if [ -n "$sta_iface_5g" ]; then
                                if [ "$force_down_5g" -gt 0 ]; then
                                    __repacd_wifimon_info " reset_bssid, up sta_iface_5g"
                                    __repacd_wifimon_bring_iface_up $sta_iface_5g
                                else
                                    __repacd_wifimon_info " reset_bssid, check sta_iface_5g is up"
                                fi
                                __repacd_wifimon_get_current_best_ap $sta_iface_5g new_bestap new_bestap_otherband
                                __repacd_wifimon_config_best_ap $sta_iface_5g $sta_iface_5g_config_name restarted config_success
                                if [ "$config_success" -gt 0 ]; then
                                    __repacd_wifimon_get_timestamp assoc_start_time
                                fi
                            fi
                            eval "$4=$WIFIMON_STATE_BSSID_ASSOC_TIMEOUT"
                        fi
                    fi
                fi

                if __repacd_wifimon_is_timeout $assoc_start_time $assoc_timeout; then
                    # If we have two STA interfaces and only 5 GHz is
                    # associated, see if mode switching is necessary for it
                    # alone. Note that here we are temporarily resetting the
                    # other interface name to ensure mode switching only
                    # considers the one that is associated.
                    #
                    # If we eventually start supporting multiple STA interfaces
                    # even in the fallback modes, we may need to make this
                    # smarter and consider both possible STA interfaces that
                    # may be associated.
                    if [ "$daisy_chain" -gt 0 ]; then
                        if [ "$nolink_detected_5g" -eq 0 ]; then
                            if [ -n "$sta_iface_24g" ]; then
                                # Even after resetting BSSIDs 5G is not associated,
                                # Now time to check on 2.4G link.
                                nolink_detected_5g=1
                                # We are left with no option, link stays disconnected
                                # till something found on 2.4G link.
                                __repacd_wifimon_debug "Waiting for association in 2.4G"
                            fi
                        else
                            local restarted config_success
                            __repacd_wifimon_get_current_best_ap $sta_iface_24g new_bestap new_bestap_otherband
                            __repacd_wifimon_config_best_ap $sta_iface_24g $sta_iface_24g_config_name restarted config_success
                            if [ "$config_success" -gt 0 ]; then
                                __repacd_wifimon_get_timestamp assoc_start_time
                            fi
                        fi
                    elif [ -n "$sta_iface_24g" -a -n "$sta_iface_5g" ]; then
                        if [ "$force_down_5g" -eq 0 ] \
                            && __repacd_wifimon_is_assoc $sta_iface_5g; then
                            local tmp_sta_iface_24g=$sta_iface_24g
                            sta_iface_24g=
                            if ! __repacd_wifimon_resolve_mode $2 $3 $5 $6; then
                                # Not currently in the right mode. Restore the
                                # interface name and return to allow for a restart.
                                sta_iface_24g=$tmp_sta_iface_24g
                                return
                            fi
                        fi
                    fi

                    if [ "$assoc_timeout_logged" -eq 0 ]; then
                        __repacd_wifimon_debug "Association timeout"
                        assoc_timeout_logged=1
                    fi

                    eval "$4=$WIFIMON_STATE_ASSOC_TIMEOUT"
                fi
            fi
        fi
        __repacd_wifimon_evaluate_backhaul_link $2 $3

        if [ "$traffic_separation_enabled" -gt 0 ] &&
               [ "$traffic_separation_active" -gt 0 ]; then
            if ! __repacd_wifimon_is_assoc $sta_iface_5g || \
               ! __repacd_wifimon_is_assoc $sta_iface_24g || [ "$guest_link_override" -gt 0 ] || \
               [ "$force_down_5g" -gt 0 ] || [ "$force_down_24g" -gt 0 ]; then
                if [ -n "$sta_iface_24g" ] && [ -n "$sta_iface_5g" ]; then
                    if [ "$guest_backhaul" = '5G' ]; then
                        __repacd_wifimon_override_guest_backhaul $sta_iface_5g $sta_iface_24g
                    elif [ "$guest_backhaul" = '2.4G' ]; then
                        __repacd_wifimon_override_guest_backhaul $sta_iface_24g $sta_iface_5g
                    fi
                fi
            fi
        fi

    fi
}
# determin does it need to down the 2.4G backhaul or wake up 2.4G backhaul
repacd_wifimon_independent_channel_check() {
    local inteface_24g
    local i=0
    local macaddress
    local channel

    if [ -n "$sta_iface_24g" ]; then
        if [ "$is_independent_channel_selection_enable" -gt 0 ]; then
            __repacd_wifimon_debug "rssi_counter=$rssi_counter rssi_check_total_counter=$rssi_check_total_counter
            force_down_24g=$force_down_24g force_down_5g=$force_down_5g sta_iface_24g=$sta_iface_24g"

            if [ "$rssi_counter" -ge "$rssi_check_total_counter" ]; then
                    if [ "$is_24G_down_by_independent_channel" -eq 0 ]; then
                        #__repacd_wifimon_debug "need to down 2.4G"

                        __repacd_wifimon_info "5G backhaul Signal is good, down the 2.4G backhaul interface and 2.4G AP VAP to do the ACS"

                        is_24G_down_by_independent_channel=1

                        uci_set wireless $wifi_2G_interface_name independent_channel_set '1'
                        uci_commit wireless

                        ((echo td s; sleep 1) | hyt | awk -F " " '/WLAN2G/ && $4 < 255 {printf "%s \n %s \n",$3,$4}' \
	                    | sed 's/[[:space:]]//g') > /tmp/innetworkresult.txt

                        # find the AP VAP for 2.4G to down the interface first
                        # then set the channel to 0
                        # then wake up all interface
                        # in multiple VAP setting ACS will re-run when All VAPs channel is 0
#                        (iwconfig | grep 'Mode:Master  Frequency:2' -B1 | sed '/wireless/d' |\
#                        sed 's/IEEE.* //g' | sed 's/Mode.* //g' | sed 's/--//g' | sed 's/[[:space:]]//g' \
#                        | sed '/^$/d') > /tmp/all_interface
                        (repacdcli wlx get_2g_ap) > /tmp/all_interface

                        exec < '/tmp/all_interface'
                        while read line
                        do
                           __repacd_wifimon_debug $line
                           inteface_24g=$line
                        done
                        # clear the in network information
                        wifitool $inteface_24g set_innetwork_2g 00:00:00:00:00:00 0
                        exec < '/tmp/innetworkresult.txt'

                        while read line
                        do
                            __repacd_wifimon_debug $line
                            if [ "$i" -eq 0 ]; then
                                macaddress=$line
                                i=$((i + 1))
                            else
                                channel=$line
                                /usr/sbin/wifitool $inteface_24g set_innetwork_2g $macaddress $channel
                                i=0
                            fi
                        done

                    __repacd_wifimon_info "Bringing down 2g $sta_iface_24g due to do ACS!"
                    xqwhc_repacd_sync_lock lock $sta_iface_24g
                        wpa_cli -p /var/run/wpa_supplicant-$sta_iface_24g disable_network 0
                    xqwhc_repacd_sync "${XQWHC_REPACD_IFDOWN}_${sta_iface_24g}" 1
                    xqwhc_repacd_sync_lock unlock $sta_iface_24g

                        device=$(uci_get misc wireless if_2G)
                        dev_channel=$(uci_get wireless $device channel)
                        __repacd_wifimon_info "device $device channel $dev_channel"
                        if [ "$dev_channel" = "0" ] || [ "$dev_channel" = "auto" ] || [ "$dev_channel" = "AUTO" ]; then
                            exec < '/tmp/all_interface'
                            while read line
                            do
                               __repacd_wifimon_debug "$line Triggering ACS"
                               iwconfig $line channel 0
                            done
                        fi
                        rm -rf /tmp/all_interface
                        rm -rf /tmp/innetworkresult.txt
                    else
                        if [ "$force_down_24g" -eq 0 ]; then
                            __repacd_wifimon_debug "5G backhaul signal is bad, up the 2.4G backhaul"
                            is_24G_down_by_independent_channel=0
                            uci_set wireless $wifi_2G_interface_name independent_channel_set '0'
                            uci_commit wireless

                            __repacd_wifimon_info "Bringing up 2g $sta_iface_24g dueto 5G snr bad!"
                            xqwhc_repacd_sync_lock lock $sta_iface_24g
                            wpa_cli -p /var/run/wpa_supplicant-$sta_iface_24g enable_network 0
                            xqwhc_repacd_sync "${XQWHC_REPACD_IFDOWN}_${sta_iface_24g}" 0
                            xqwhc_repacd_sync_lock unlock $sta_iface_24g
                        else
                            __repacd_wifimon_debug "2.4G backhaul interface is down by anohter process don't wake up it"
                       fi
                   fi
                    rssi_counter=0
            fi
        fi
    else
        __repacd_wifimon_debug "sta_iface_24g=$sta_iface_24g is null, cannot do anything"
    fi
}
# Terminate the Wi-Fi link monitoring, cleaning up any state in preparation
# for shutdown.
repacd_wifimon_fini() {

    __repacd_wifimon_debug "sta_iface_24g=$sta_iface_24g is_24G_down_by_independent_channel=$is_24G_down_by_independent_channel force_down_24g=$force_down_24g"

    if [ -n "$sta_iface_24g" ]; then
        if [ "$is_24G_down_by_independent_channel" -gt 0 ]; then
            if [ "$force_down_24g" -eq 0 ]; then
                uci_set wireless $wifi_2G_interface_name independent_channel_set '0'
                uci_commit wireless

                __repacd_wifimon_info "Bringing up 2g $sta_iface_24g dueto wifimon_fini!"
                xqwhc_repacd_sync_lock lock $sta_iface_24g
                wpa_cli -p /var/run/wpa_supplicant-$sta_iface_24g enable_network 0
                xqwhc_repacd_sync "${XQWHC_REPACD_IFDOWN}_${sta_iface_24g}" 0
                xqwhc_repacd_sync_lock unlock $sta_iface_24g
            fi
        fi
    fi
    __repacd_stop_ping
}
