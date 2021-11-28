#!/bin/sh
# Copyright (c) 2015-2018 Qualcomm Technologies, Inc.
# All Rights Reserved.
# Confidential and Proprietary - Qualcomm Technologies, Inc.
#
# 2015-2016 Qualcomm Atheros, Inc.
# All Rights Reserved.
# Qualcomm Atheros Confidential and Proprietary.

REPACD_DEBUG_OUTOUT=0

. /lib/functions/repacd-lp.sh
. /lib/functions/repacd-gwmon.sh
. /lib/functions/repacd-led.sh

GWMON_DEBUG_OUTOUT=$REPACD_DEBUG_OUTOUT

cur_role='' managed_network=''
link_check_delay=''
restart_wifi=0
traffic_separation_enabl=0
traffic_separation_activ=0
backhaul_network=''
eth_mon_enabled=''
miwifi_ethbh_mono_en=0

__repacd_info() {
    local stderr=''
    if [ "$REPACD_DEBUG_OUTOUT" -gt 0 ]; then
        stderr='-s'
    fi

    logger $stderr -t repacd-run -p user.info "$1"
}

__repacd_debug() {
    local stderr=''
    if [ "$REPACD_DEBUG_OUTOUT" -gt 0 ]; then
        stderr='-s'
    fi

    logger $stderr -t repacd-run -p user.debug "$1"
}

__repacd_warn()
{
    local stderr=''
    if [ "$REPACD_DEBUG_OUTOUT" -gt 0 ]; then
        stderr='-s'
    fi

    logger $stderr -t repacd-run -p user.warn "$1"
}

__repacd_restart() {
    local __mode="$1"
    __repacd_info "repacd: restart in $__mode mode"

    /etc/init.d/repacd "restart_in_${__mode}_mode"
    exit 0
}

__repacd_update_mode() {
    local new_mode=$1
    if [ "$new_mode" -eq "$GWMON_MODE_CAP" ]; then
        __repacd_info "Restarting in CAP mode"
        __repacd_restart 'cap'
    elif [ "$new_mode" -eq "$GWMON_MODE_NON_CAP" ]; then
        if [ "$alg_set" = "map" ]; then
            repacd_wifimon_config_bsta "${managed_network}"
        fi

        __repacd_info "Restarting in NonCAP mode"

        [ "$miwifi_ethbh_mono_en"  -gt 0 ] && {
            # prev state is eth bh, so must bring up wlan & plc bhs
            __repacd_warn "miwifi, bring up other bhs @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
            [ -n "$sta_iface_5g" ] && {
                __repacd_wifimon_bring_iface_up $sta_iface_5g
                cfg80211tool $sta_iface_5g whc_mixedbh_ul 0
                cfg80211tool $sta_iface_5g whc_mixedbh_bh_type 1
                __repacd_warn " miwifi WA wifi-RE -$sta_iface_5g- whc_mixedbh_bh_type>1, whc_mixedbh_ul>0!"
            }
            [ -n "$sta_iface_24g" ] && {
                __repacd_wifimon_bring_iface_up $sta_iface_24g
                cfg80211tool $sta_iface_24g whc_mixedbh_ul 0
                cfg80211tool $sta_iface_24g whc_mixedbh_bh_type 1
                __repacd_warn " miwifi WA wifi-RE -$sta_iface_24g- whc_mixedbh_bh_type>1, whc_mixedbh_ul>0!"
            }
            #__repacd_plcmon_bring_plc_iface_up
        }

        __repacd_restart 'noncap'

    elif [ "$new_mode" -eq "$GWMON_MODE_NON_CAP_ETH" ]; then
        __repacd_warn "miwifi Handling RE mode with eth backhaul on $gw_iface @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
        ### TODO
        #__repacd_warn "@@@ off wlan & plc bh immediate ?? "

        miwifi_ethbh_mono_en=1
        __repacd_warn "miwifi ignore wifimon check in eth bh situation!"

        ### workaround for RE bcast below eth-RE. set backhaul rate for RE below to assoc this RE.
        #gw_ip=$(route -n | grep ^0.0.0.0 | grep "br-lan" | awk '{print $2}')
        #gw_addr=$(arp -a | grep "$gw_ip" | grep "br-lan" | awk '{print $4}')
        local gw_addr=$(echo "$gw_mac" | sed 's/:/-/g')
        local gw_switch_port_num=$(ssdk_sh fdb entry show |grep -i $gw_addr |awk -F':' '{print $5}' |sed 's/ //g' |head -1)
        local gw_port_link_info=$(swconfig dev switch0 port $gw_switch_port_num get link)
        local gw_link_status="$(echo $gw_port_link_info |awk -F':' '{print $3}'|awk -F ' ' '{print $1}')"
        __repacd_warn " miwifi WA eth-RE gw_addr:$gw_addr, gw_switch_port_num:$gw_switch_port_num, gw_link_status:$gw_link_status!"
        if [ "$gw_link_status" = "up" ]; then
            local gw_link_rate=$(echo $gw_port_link_info |awk -F':' '{print $4}'|awk -F 'baseT' '{print $1}')
            . /lib/xqwhc/network_lal.sh
            local list
            nlal_get_wifi_apiface_bynet lan list
            for ifn in $list; do
                # set apif backhaul rate for possible RE below.
                cfg80211tool $ifn whc_mixedbh_ul $gw_link_rate
                cfg80211tool $ifn whc_mixedbh_bh_type 2
                __repacd_warn " miwifi WA eth-RE $ifn whc_mixedbh_bh_type>2, whc_mixedbh_ul>$gw_link_rate!"
            done
        fi
    fi
}

# check gw_iface if is an eth iface
# call in main loop in case gwmon NOT send router_detect??
__miwifi_repacd_check_eth_bh()
{
    __repacd_info "@@@ miwifi check eth bh, gw_iface=$gw_iface, eth_bridge_eth_ifaces=$bridge_eth_ifaces"

    if echo $bridge_eth_ifaces | grep -q $gw_iface; then
        miwifi_ethbh_mono_en = 1
    fi
}

__repacd_wifimon_init() {

    if [ "$traffic_separation_enabl" -gt 0 ] && \
       [ "$traffic_separation_activ" -gt 0 ]; then
        repacd_wifimon_init "$backhaul_network" "$current_re_mode" "$current_re_submode" "$autoconf_restart" \
                            new_state new_re_mode new_re_submode
    else
        repacd_wifimon_init $managed_network "$current_re_mode" "$current_re_submode" "$autoconf_restart" \
                            new_state new_re_mode new_re_submode
    fi

    __repacd_debug " @@ __repacd_wifimon_init new state $new_state; re_mode $new_re_mode; re_submode $new_re_submode autoconf=$autoconf_restart"

}

config_load repacd
config_get managed_network repacd 'ManagedNetwork' 'lan'
config_get cur_role repacd 'Role' 'NonCAP'
config_get link_check_delay repacd 'LinkCheckDelay' '2'
config_get traffic_separation_enabl repacd TrafficSeparationEnabled '0'
config_get traffic_separation_activ repacd TrafficSeparationActive '0'
config_get backhaul_network repacd NetworkBackhaul 'backhaul'
config_get eth_mon_enabled repacd 'EnableEthernetMonitoring' '0'

if [ "$#" -lt 5 ]; then
    echo -n "Usage: $0 <alg_set> <start_role> <config RE mode> "
    echo "<current RE mode> <current RE submode> [autoconf]"
    exit 1
fi

alg_set=$1
start_role=$2
config_re_mode=$3
current_re_mode=$4
current_re_submode=$5
re_mode_change=0

if [ "$alg_set" = "son" ]; then
    . /lib/functions/repacd-wifimon.sh
    . /lib/functions/repacd-ethmon.sh
    . /lib/functions/repacd-netdet.sh
    . /lib/functions/repacd-backhaulmgr.sh
    . /lib/functions/repacd-plcmon.sh
    . /lib/functions/repacd-fronthaulmgr.sh
elif [ "$alg_set" = "map" ]; then
    . /lib/functions/repacd-wifimon-map.sh
    . /lib/functions/repacd-fronthaulmgr.sh
fi

# Clean up the background ping and related logic when being terminated
# by the init system.
handle_sig()
{
    repacd_wifimon_fini;
    repacd_led_set_states Reset;
    [ -n $sta_iface_5g ] && xqwhc_repacd_sync_lock unlock $sta_iface_5g
    [ -n $sta_iface_24g ] && xqwhc_repacd_sync_lock unlock $sta_iface_24g
}

trap 'handle_sig; exit 0' SIGTERM

__repacd_info "Starting: Algorithm set=$alg_set"
__repacd_info "Starting: ConfiguredRole=$cur_role StartRole=$start_role #############################################################"
__repacd_info "Starting: ConfigREMode=$config_re_mode CurrentREMode=$current_re_mode CurrentRESubMode=$current_re_submode"

cur_state='' new_state=''
new_re_mode=$current_re_mode new_re_submode=$current_re_submode
autoconf_restart=''

new_mode=
__gwmon_init $cur_role "$start_role" $managed_network
new_mode=$?
if [ "$eth_mon_enabled" -eq 0 ] || [ ${new_mode} -ne "$GWMON_MODE_NO_CHANGE" ]; then
    __repacd_update_mode $new_mode
fi

# If the start was actually a restart triggered by automatic configuration
# logic (eg. mode or role switching), note that here so it can influence the
# LED states.
if [ -n "$6" ]; then
    __repacd_info "Startup triggered by auto-config change"
    autoconf_restart=1
else
    autoconf_restart=0
fi

if [ ! "$eth_mon_enabled" -eq 0 ]; then
    repacd_lp_init
    repacd_netdet_init
fi

# Initialise Wi-Fi monitoring logic
__repacd_wifimon_init

# Since the Wi-Fi monitoring process does nothing when in CAP mode, force
# the state to one that indicates we are operating in CAP mode.
if [ "$cur_role" = 'CAP' ]; then
    new_state='InCAPMode'
else
    if [ "$alg_set" = "son" ]; then
        # Initialise Backhaul Manager logic for REs
        repacd_backhaulmgrmon_init
        repacd_plcmon_init
    fi

    # This is valid in both SON and MAP modes
    repacd_fronthaulmgrmon_init
fi


if [ -n "$new_state" ]; then
    #__repacd_info "Setting initial LED states to $new_state"
    #repacd_led_set_states $new_state
    cur_state=$new_state
else
    __repacd_info "Failed to resolve STA interface; will attempt periodically"
fi

# Loop forever (unless we are killed with SIGTERM which is handled above).
while true; do
    __gwmon_check
    new_mode=$?
    __repacd_update_mode $new_mode

  if [ "$miwifi_ethbh_mono_en" -eq 0 ]; then
    __repacd_debug " @@wifi state=$cur_state "
    if [ -n "$cur_state" ]; then
        new_state=''
        repacd_wifimon_check $managed_network "$current_re_mode" "$current_re_submode" \
                             new_state new_re_mode new_re_submode

        # First test for range extender mode change, which could also include
        # a role change if the LED state is updated to indicate that.
        re_mode_change=0
        if [ "$config_re_mode" = 'auto' ] && \
             [ ! "$current_re_mode" = "$new_re_mode" ]; then
            __repacd_info "New auto-derived RE mode=$new_re_mode"

            uci_set repacd repacd AssocDerivedREMode "$new_re_mode"
            uci_set repacd WiFiLink BSSIDResolveState 'resolving'
            uci_commit repacd

            re_mode_change=1
        fi

        # RE sub-mode change check.
        if [ ! "$current_re_submode" = "$new_re_submode" ]; then
            __repacd_info "New auto-derived RE sub-mode=$new_re_submode, cur=$current_re_submode"

            uci_set repacd repacd AssocDerivedRESubMode "$new_re_submode"
            uci_commit repacd

            # As of now, no special handling required for "star" and "daisy" submodes.
            # So just keep the Current and New RE-submode in sync.
            current_re_submode=$new_re_submode

            ###################################################
            # miwifi: if sub-mode star, make sure bringup WLAN sta and plc, in case it had brought down in daisy-chain
            ###################################################
            if [ "$current_re_submode" = "star" ]; then
                __repacd_info " sub-mode to star, Bringing up WLAN & plc interface..."
                [ -n $sta_iface_5g ] && __repacd_wifimon_bring_iface_up $sta_iface_5g
                [ -n $sta_iface_24g ] && __repacd_wifimon_bring_iface_up $sta_iface_24g
                #__repacd_plcmon_bring_plc_iface_up
            fi
        fi

        if [ -n "$new_state" ] && [ ! "$new_state" = "$cur_state" ]; then
            #__repacd_info "Updating LED states to $new_state"
            #repacd_led_set_states $new_state

            cur_state=$new_state

            # Depending on the startup role, look for the special states
            # that indicate the new role should be different.
            if [ ! "$start_role" = 'RE' ]; then  # init and NonCAP roles
                if [ "$new_state" = "$WIFIMON_STATE_CL_ACTING_AS_RE" ]; then
                    __repacd_info "Restarting in RE role"
                    __repacd_restart 're'
                    re_mode_change=0  # role change includes mode change
                fi
            elif [ "$start_role" = 'RE' ]; then
                if [ "$new_state" = "$WIFIMON_STATE_CL_LINK_INADEQUATE" ] || \
                     [ "$new_state" = "$WIFIMON_STATE_CL_LINK_SUFFICIENT" ]; then
                    __repacd_info "Restarting in Client role"
                    __repacd_restart 'noncap'
                    re_mode_change=0  # role change includes mode change
                fi
            fi

            if [ "$new_state" = "$WIFIMON_STATE_RE_SWITCH_BSTA" ]; then
                __repacd_info "Restarting due to bSTA switch"
                __repacd_restart 're'
            elif [ "$new_state" = "$WIFIMON_STATE_RE_BACKHAUL_GOOD" ] ||
                [ "$new_state" = "$WIFIMON_STATE_RE_BACKHAUL_FAIR" ] ||
                [ "$new_state" = "$WIFIMON_STATE_RE_BACKHAUL_POOR" ]; then

                uci_set repacd FrontHaulMgr ForceDownOnStart 0
                uci_commit repacd

                # Perform special handling for the bBSS interfaces.
                if [ "$new_state" = "$WIFIMON_STATE_RE_BACKHAUL_POOR" ]; then
                    repacd_fronthaulmgrmon_bring_down_bBSSes
                fi
            fi
        fi

        if [ "$new_state" = "$WIFIMON_STATE_RE_BACKHAUL_GOOD" ] ||
            [ "$new_state" = "$WIFIMON_STATE_RE_BACKHAUL_FAIR" ]; then
            # This will normally be a nop, but is done here instead of only
            # during a state change just in case the bBSSes do not all come
            # up successfully the first time the ifconfig is run.
            repacd_fronthaulmgrmon_bring_up_bBSSes
        fi

        # Handle any RE mode change not implicitly handled above.
        if [ "$re_mode_change" -gt 0 ]; then
            if [ ! "$start_role" = 'RE' ]; then  # init and NonCAP roles
                __repacd_restart 'noncap'
            elif [ "$start_role" = 'RE' ]; then
                __repacd_restart 're'
            fi
        fi

        # if restart_wifi and re_mode_change is not start
        # go to determing if 2.4G backhaul interface need to down or not
        if [ "$restart_wifi" -eq 0 ]; then
            if [ "$re_mode_change" -eq 0 ]; then
                repacd_wifimon_independent_channel_check
            fi
        fi
    else
        # Initialise Wi-Fi monitoring logic
        __repacd_wifimon_init

        if [ -n "$new_state" ]; then
            #__repacd_info "Setting initial LED states to $new_state"
            #repacd_led_set_states $new_state
            cur_state=$new_state
        fi
    fi
  else
    #__repacd_debug "miwifi ignore wifimon check in eth bh situation!"
    :
  fi ## end if miwifi_ethbh_mono_en

    if [ "$eth_mon_enabled" -eq 1 ]; then
        repacd_ethmon_check
    fi

    if [ "$cur_role" != 'CAP' ] && [ "$alg_set" = "son" ]; then
        repacd_backhaulmgrmon_check
    fi

    if [ "$cur_role" != 'CAP' ]; then
        repacd_fronthaulmgrmon_check
    fi

    # Re-check the link conditions in a few seconds.
    sleep $link_check_delay
done
