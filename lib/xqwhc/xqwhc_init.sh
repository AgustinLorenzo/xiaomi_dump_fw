#!/bin/sh 

# whc upper abstract layer support

. /lib/xqwhc/xqwhc_public.sh
. /lib/xqwhc/xqwhc_stat.sh
. /lib/xqwhc/network_lal.sh
. /lib/xqwhc/xqwhc_hyt.sh
. /lib/xqwhc/xqwhc_metric.sh

# argin as json string, extract params from whc_ual

ERR_INIT=1
ERR_PARAM_INV=2
ERR_PARAM_NONE=3
nw_cfg="/tmp/log/nw_cfg"
#bh_mgmt="psk2+ccmp"

usage()
{
    echo "$0 usage:"
    echo "$0 init $jstr: init with $jstr "
    echo "$0 delete: deinit dev to default mode/factory mode"
    echo ""
    echo "$0 get_wifi: get wifi config "
    echo "$0 set_wifi $jstr: set wifi "
    echo ""
    echo "$0 get_topology: son topology info, include RE addr and backhauls with father/child nodes "
    echo "$0 get_status $node_addr: get RE node info, include self and bridged device"
}


# xqmode: 1 setmode 0 clearmode
# mode: whc_cap/whc_re is used for trafficd tbus
__set_xqmode()
{
    local swt="$1"

    # netmode
    if [ "$swt" -eq 0 ]; then
        uci -q delete xiaoqiang.common.NETMODE
        nvram set mode=Router
    else
        local mode="whc_$2"
        uci -q set xiaoqiang.common.NETMODE="$mode"

        [ "$2" = re ] && nvram set mode=AP || nvram set mode=Router
    fi

    uci commit xiaoqiang
    nvram commit

    return 0
}

__enable_hyfi_bridge()
{
    # enable to make sure bcast-loop ahead of init.
    sysctl -w net.bridge.bridge-nf-call-custom=1
}

__init_son()
{
    WHC_LOGI " setup son cfg on $whc_role "

    ### disable mcsd (as it cannot run at the same time as hyd)
    [ -f /etc/init.d/mcsd ] && {
        uci -q set mcsd.config.Enable=0
        uci commit mcsd
        /etc/init.d/mcsd stop
        /etc/init.d/mcsd disable
    }

    ### lbd
    # use cfg lbd.config-mesh for mesh mode
    cp /etc/lbd.config-mesh /etc/config/lbd
    uci -q delete lbd.config.MatchingSSID
    if [ "$bsd" -eq 0 ]; then
        local dis_2g="`uci -q get wireless.@wifi-iface[1].disabled`"
        local dis_5g="`uci -q get wireless.@wifi-iface[0].disabled`"
        # assign public wifi-iface ssid, exclude minet_ready from hyd Wlanif
        [ "0$dis_2g" -ne "1" ] && uci add_list lbd.config.MatchingSSID="$ssid_2g"
        [ "$ssid_5g" != "$ssid_2g" ] && {
            [ "0$dis_5g" -ne "1" ] && uci add_list lbd.config.MatchingSSID="$ssid_5g"
        }
        uci -q set lbd.config.PHYBasedPrioritization=0
    else
        uci add_list lbd.config.MatchingSSID="$whc_ssid"
        uci -q set lbd.config.PHYBasedPrioritization=1
    fi
    [ "$BH_METHOD" -eq "$USE_ONLY_5G_IND_VAP_BH" -o "$BH_METHOD" -eq "$USE_DUAL_BAND_IND_VAP_BH" ] && {
        local bh_ifname="`uci get misc.backhauls.backhaul_5g_ap_iface`"
        local bh_ssid="`uci get "$(uci show wireless | awk -F 'ifname' '/'$bh_ifname'/{print $1}')ssid"`"
        [ -n "$bh_ssid" ] && uci add_list lbd.config.MatchingSSID="$bh_ssid" # assign bh ssid
    }
    uci commit lbd

    ### hyd  autoset in repacd start
    # miwifi: set hy ForwardingMode to SINGLE from APS if using single backhaul
    [ "$BH_METHOD" -eq "$USE_ONLY_5G_BH" -o "$BH_METHOD" -eq "$USE_ONLY_5G_IND_VAP_BH" ] && {
        uci -q set hyd.hy.ForwardingMode='SINGLE'
        uci commit hyd
    }

    [ "$XQWHC_DEBUG" = "1" ] && {
        [ -f /etc/init.d/wsplcd ] && {
            uci -q set wsplcd.config.DebugLevel="DEBUG"
            uci -q set wsplcd.config.WriteDebugLogToFile="APPEND"
            uci commit wsplcd
        }
    }

    ### re Range Extender Placement and Auto-configuration Daemon
    uci -q set repacd.repacd.Enable=1
    uci -q set repacd.WiFiLink.DaisyChain=1
    uci -q set repacd.repacd.ConfigREMode=son
    # miwifi: we need CAP must be router-mode, thus app/web UI must assure that wan is configed before repacd init as CAP.
    # in bsp layer we ignore automatic decision of non-CAP by below option
    if [ "$whc_role" = "CAP" ]; then
        uci -q set repacd.repacd.miwifi_mode="whc_cap"
    else
        uci -q set repacd.repacd.miwifi_mode="whc_re"
        uci -q set repacd.repacd.DefaultREMode=son
        uci -q set repacd.WiFiLink.ManageVAPInd=1
    fi

    uci commit repacd

    uci set network.lan.multicast_querier='1'
    uci set network.lan.igmp_snooping='1'

	uci commit network
}

__start_son()
{
    sync

    WHC_LOGI " start son service on $whc_role "

    if [ "$whc_role" = "RE" ] && [ -f "$nw_cfg" ]; then
        /etc/init.d/repacd init_in_re_mode
        mv $nw_cfg ${nw_cfg}.bak
    else
        /etc/init.d/repacd restart
    fi

    [ -f /etc/init.d/qrfs ] && {
        /etc/init.d/qrfs stop
        /etc/init.d/qrfs disable
    }
}

__delete_son()
{
    WHC_LOGI "      deleting son..."

    # disable repacd, wsplcd, hyd
    /etc/init.d/repacd stop
    [ -f /etc/init.d/wsplcd ] && /etc/init.d/wsplcd stop
    /etc/init.d/hyd stop

    /etc/init.d/xiaoqiang_sync stop

    uci -q set repacd.repacd.Enable=0
    uci -q set repacd.repacd.Role='NonCAP'
    # restore to avoid guest
    uci -q set repacd.repacd.miwifi_mode="none"

    [ -f /etc/init.d/wsplcd ] && uci -q set wsplcd.config.HyFiSecurity=0
    uci -q set hyd.config.Enable=0
    uci -q set lbd.config.Enable=0
    uci -q delete lbd.config.MatchingSSID
    uci commit

    # restore mcsd
    [ -f /etc/init.d/mcsd ] && {
        uci -q set mcsd.config.Enable=1
        uci commit mcsd
        /etc/init.d/mcsd enable
    }
}

__delete_wifi()
{
    WHC_LOGI "      deleting wifi..."

    # backup guest vap iface
    local sguest="$(uci -q get misc.wireless.iface_guest_2g_name)"
    [ -z "$sguest" ] && sguest=guest_2G
    if uci -q get wireless.${sguest} >/dev/null 2>&1; then
        opts="`uci show wireless | grep wireless.${sguest}`"
    fi

    # wifi cfg restore
    ### wifi down;  # how about we do NOT wifi down first
    (rm /etc/config/wireless; wifi detect >/etc/config/wireless 2>/dev/null; sync; /sbin/wifi reload_legacy)

    # config restore vap iface and maintain guest
    [ "$role"  = "CAP" -a -n "$opts" ] && {
        for opt in $opts; do
            uci -q set "$opt"
        done
        uci commit wireless
    } 

}

# check bh white mac_list, return mac_list if valid
# $1 input type, 2g/5g
# $2 output mac_list after check
__check_bh_vap_mac_list()
{
    local mac_idx mac_list_t mac
    local type="$1"
    local macnum="`eval echo '$'{bh_macnum_"${type}"g}`"
    local maclist="`eval echo '$'{bh_maclist_"${type}"g}`"
    [ -n "${maclist}" ] && {
        for mac_idx in $(seq 1 ${macnum}); do
            mac="`echo $maclist | awk -F ',' '{print $jj}' jj="$mac_idx"`"
            mac="`echo $mac | sed 's/ //g' | sed 'y/abcdef/ABCDEF/'`"
            echo "$mac" | grep -q -o -E '^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$' && {
                mac_list_t="${mac_list_t}${mac_list_t:+","}${mac}"
            }
        done
    }
    eval "$2=$mac_list_t"
}

__init_wifi_cap()
{
    WHC_LOGI " setup wifi cfg on CAP "

    local guest_cfg="/tmp/log/sguest"
    local iface_list="" ii=0 iface_idx_start=2
    local main_ssid main_mgmt main_pswd
    ifconfig wifi2 >/dev/null 2>&1 && export WIFI2_EXIST=1 || export WIFI2_EXIST=0
    [ "$WIFI2_EXIST" = "1" ] && iface_idx_start=3 || iface_idx_start=2

    # backup guest vap cfg and restore later
    local sguest="$(uci -q get misc.wireless.iface_guest_2g_name)"
    [ -z "$sguest" ] && sguest=guest_2G
    if uci -q get wireless.${sguest} >/dev/null 2>&1; then
        opts="`uci show wireless | grep wireless.${sguest}`"
    fi
    echo "$opts" > ${guest_cfg}
    uci -q delete wireless.${sguest}

    case "$BH_METHOD" in
        $USE_DUAL_BAND_BH)
            # wifi ap ifaces
            iface_list="0 1"
            for ii in ${iface_list}; do
                if [ "$bsd" -eq 0 ]; then
                    [ "$ii" -eq 0 ] && {
                        main_ssid=$ssid_5g
                        main_mgmt=$mgmt_5g
                        main_pswd=$pswd_5g
                    } || {
                        main_ssid=$ssid_2g
                        main_mgmt=$mgmt_2g
                        main_pswd=$pswd_2g
                    }
                else
                    main_ssid=$whc_ssid
                    main_mgmt=$whc_mgmt
                    main_pswd=$whc_pswd
                fi
                uci -q batch <<-EOF >/dev/null
set wireless.@wifi-iface[$ii].ssid="$main_ssid"
set wireless.@wifi-iface[$ii].encryption="$main_mgmt"
set wireless.@wifi-iface[$ii].key="$main_pswd"
set wireless.@wifi-iface[$ii].backhaul='1'
set wireless.@wifi-iface[$ii].backhaul_ap='1'
set wireless.@wifi-iface[$ii].wnm='1'
set wireless.@wifi-iface[$ii].wds='1'
set wireless.@wifi-iface[$ii].rrm='1'
set wireless.@wifi-iface[$ii].wps_pbc='1'
set wireless.@wifi-iface[$ii].wps_pbc_enable='0'
set wireless.@wifi-iface[$ii].wps_pbc_start_time='0'
set wireless.@wifi-iface[$ii].wps_pbc_duration='120'
set wireless.@wifi-iface[$ii].group='0'
EOF
                case "$main_mgmt" in
                    none)
                        uci -q delete wireless.@wifi-iface[$ii].key
                    ;;
                    mixed-psk|psk2)
                    ;;
                    psk2+ccmp)
                        uci -q set wireless.@wifi-iface[$ii].sae='1'
                        uci -q set wireless.@wifi-iface[$ii].sae_password="$main_pswd"
                        uci -q set wireless.@wifi-iface[$ii].ieee80211w='1'
                    ;;
                    ccmp)
                        uci -q delete wireless.@wifi-iface[$ii].key
                        uci -q set wireless.@wifi-iface[$ii].sae='1'
                        uci -q set wireless.@wifi-iface[$ii].sae_password="$main_pswd"
                        uci -q set wireless.@wifi-iface[$ii].ieee80211w='2'
                    ;;
                esac
            done

        ;;
        $USE_ONLY_5G_BH)
            # wifi ap ifaces
            iface_list="0 1"
            for ii in ${iface_list}; do
                if [ "$bsd" -eq 0 ]; then
                    [ "$ii" -eq 0 ] && {
                        main_ssid=$ssid_5g
                        main_mgmt=$mgmt_5g
                        main_pswd=$pswd_5g
                    } || {
                        main_ssid=$ssid_2g
                        main_mgmt=$mgmt_2g
                        main_pswd=$pswd_2g
                    }
                else
                    main_ssid=$whc_ssid
                    main_mgmt=$whc_mgmt
                    main_pswd=$whc_pswd
                fi
                uci -q batch <<-EOF >/dev/null
set wireless.@wifi-iface[$ii].ssid="$main_ssid"
set wireless.@wifi-iface[$ii].encryption="$main_mgmt"
set wireless.@wifi-iface[$ii].key="$main_pswd"
set wireless.@wifi-iface[$ii].wnm='1'
set wireless.@wifi-iface[$ii].rrm='1'
EOF
                case "$main_mgmt" in
                    none)
                        uci -q delete wireless.@wifi-iface[$ii].key
                    ;;
                    mixed-psk|psk2)
                    ;;
                    psk2+ccmp)
                        uci -q set wireless.@wifi-iface[$ii].sae='1'
                        uci -q set wireless.@wifi-iface[$ii].sae_password="$main_pswd"
                        uci -q set wireless.@wifi-iface[$ii].ieee80211w='1'
                    ;;
                    ccmp)
                        uci -q delete wireless.@wifi-iface[$ii].key
                        uci -q set wireless.@wifi-iface[$ii].sae='1'
                        uci -q set wireless.@wifi-iface[$ii].sae_password="$main_pswd"
                        uci -q set wireless.@wifi-iface[$ii].ieee80211w='2'
                    ;;
                esac
            done
            uci -q set wireless.@wifi-iface[0].backhaul='1'
            uci -q set wireless.@wifi-iface[0].backhaul_ap='1'
            uci -q set wireless.@wifi-iface[0].wds='1'
            uci -q set wireless.@wifi-iface[0].wps_pbc='1'
            uci -q set wireless.@wifi-iface[0].wps_pbc_enable='0'
            uci -q set wireless.@wifi-iface[0].wps_pbc_start_time='0'
            uci -q set wireless.@wifi-iface[0].wps_pbc_duration='120'
            uci -q set wireless.@wifi-iface[0].group='0'
        ;;
        $USE_ONLY_5G_IND_VAP_BH)
            # wifi ap ifaces
            iface_list="0 1"
            for ii in ${iface_list}; do
                if [ "$bsd" -eq 0 ]; then
                    [ "$ii" -eq 0 ] && {
                        main_ssid=$ssid_5g
                        main_mgmt=$mgmt_5g
                        main_pswd=$pswd_5g
                    } || {
                        main_ssid=$ssid_2g
                        main_mgmt=$mgmt_2g
                        main_pswd=$pswd_2g
                    }
                else
                    main_ssid=$whc_ssid
                    main_mgmt=$whc_mgmt
                    main_pswd=$whc_pswd
                fi
                uci -q set wireless.@wifi-iface[$ii].ssid="$main_ssid"
                uci -q set wireless.@wifi-iface[$ii].encryption="$main_mgmt"
                uci -q set wireless.@wifi-iface[$ii].key="$main_pswd"
                uci -q batch <<-EOF >/dev/null
set wireless.@wifi-iface[$ii].wnm='1'
set wireless.@wifi-iface[$ii].rrm='1'
set wireless.@wifi-iface[$ii].wsplcd_unmanaged='1'
set wireless.@wifi-iface[$ii].repacd_security_unmanaged='1'
set wireless.@wifi-iface[$ii].disabled='0'
EOF
                case "$main_mgmt" in
                    none)
                        uci -q delete wireless.@wifi-iface[$ii].key
                    ;;
                    mixed-psk|psk2)
                    ;;
                    psk2+ccmp)
                        uci -q set wireless.@wifi-iface[$ii].sae='1'
                        uci -q set wireless.@wifi-iface[$ii].sae_password="$main_pswd"
                        uci -q set wireless.@wifi-iface[$ii].ieee80211w='1'
                    ;;
                    ccmp)
                        uci -q delete wireless.@wifi-iface[$ii].key
                        uci -q set wireless.@wifi-iface[$ii].sae='1'
                        uci -q set wireless.@wifi-iface[$ii].sae_password="$main_pswd"
                        uci -q set wireless.@wifi-iface[$ii].ieee80211w='2'
                    ;;
                esac
            done

            # setup 5G ind bh ap ifaces
:<<!
            local bh_ifname="`uci get misc.backhauls.backhaul_5g_ap_iface`"
            [ -z "$whc_mac" ] && whc_mac="`getmac wl1`"
            local mac_b5=$(echo $whc_mac | cut -d ':' -f 5)
            local mac_b6=$(echo $whc_mac | cut -d ':' -f 6)
            local uid=$(printf "%04X" $((0x$mac_b5$mac_b6)))
            local bh_ssid="${BHPREFIX}_${uid}"
            local bh_mgmt="$bh_defmgmt"
            local bh_passwd="$(xor_sum "$bh_ssid" "$whc_mac")"
!
            local bh_ifname="`uci get misc.backhauls.backhaul_5g_ap_iface`"
            ii=$iface_idx_start
            uci -q batch <<-EOF >/dev/null
add wireless wifi-iface
set wireless.@wifi-iface[$ii].device='wifi0'
set wireless.@wifi-iface[$ii].ifname="$bh_ifname"
set wireless.@wifi-iface[$ii].network='lan'
set wireless.@wifi-iface[$ii].mode='ap'
set wireless.@wifi-iface[$ii].channel_block_list='52,56,60,64'
set wireless.@wifi-iface[$ii].ssid="$bh_ssid"
set wireless.@wifi-iface[$ii].encryption="$bh_mgmt"
set wireless.@wifi-iface[$ii].key="$bh_pswd"
set wireless.@wifi-iface[$ii].hidden='1'
set wireless.@wifi-iface[$ii].backhaul='1'
set wireless.@wifi-iface[$ii].backhaul_ap='1'
set wireless.@wifi-iface[$ii].wds='1'
set wireless.@wifi-iface[$ii].wps_pbc='1'
set wireless.@wifi-iface[$ii].wps_pbc_enable='0'
set wireless.@wifi-iface[$ii].wps_pbc_start_time='0'
set wireless.@wifi-iface[$ii].wps_pbc_duration='120'
set wireless.@wifi-iface[$ii].wsplcd_unmanaged='1'
set wireless.@wifi-iface[$ii].repacd_security_unmanaged='1'
set wireless.@wifi-iface[$ii].group='0'
EOF
            local mac_list
            __check_bh_vap_mac_list "5" mac_list
            [ -n "$mac_list" ] && {
                mac_list="`echo $mac_list | sed "s/,/ /g"`"
                uci -q set wireless.@wifi-iface[$ii].macfilter='allow'
                uci -q delete wireless.@wifi-iface[$ii].maclist
                for mac in $mac_list; do
                    uci -q add_list wireless.@wifi-iface[$ii].maclist="$mac"
                done
            }
        ;;
        # default USE_DUAL_BAND_IND_VAP_BH
        $USE_DUAL_BAND_IND_VAP_BH | *)
            # wifi ap ifaces
            iface_list="0 1"
            for ii in ${iface_list}; do
                if [ "$bsd" -eq 0 ]; then
                    [ "$ii" -eq 0 ] && {
                        main_ssid=$ssid_5g
                        main_mgmt=$mgmt_5g
                        main_pswd=$pswd_5g
                    } || {
                        main_ssid=$ssid_2g
                        main_mgmt=$mgmt_2g
                        main_pswd=$pswd_2g
                    }
                else
                    main_ssid=$whc_ssid
                    main_mgmt=$whc_mgmt
                    main_pswd=$whc_pswd
                fi
                uci -q set wireless.@wifi-iface[$ii].ssid="$main_ssid"
                uci -q set wireless.@wifi-iface[$ii].encryption="$main_mgmt"
                uci -q set wireless.@wifi-iface[$ii].key="$main_pswd"
                uci -q batch <<-EOF >/dev/null
set wireless.@wifi-iface[$ii].wnm='1'
set wireless.@wifi-iface[$ii].rrm='1'
set wireless.@wifi-iface[$ii].wsplcd_unmanaged='1'
set wireless.@wifi-iface[$ii].repacd_security_unmanaged='1'
EOF
                case "$main_mgmt" in
                    none)
                        uci -q delete wireless.@wifi-iface[$ii].key
                    ;;
                    mixed-psk|psk2)
                    ;;
                    psk2+ccmp)
                        uci -q set wireless.@wifi-iface[$ii].sae='1'
                        uci -q set wireless.@wifi-iface[$ii].sae_password="$main_pswd"
                        uci -q set wireless.@wifi-iface[$ii].ieee80211w='1'
                    ;;
                    ccmp)
                        uci -q delete wireless.@wifi-iface[$ii].key
                        uci -q set wireless.@wifi-iface[$ii].sae='1'
                        uci -q set wireless.@wifi-iface[$ii].sae_password="$main_pswd"
                        uci -q set wireless.@wifi-iface[$ii].ieee80211w='2'
                    ;;
                esac
            done

            # setup dual band ind bh ap ifaces
            local bh_device bh_ifname
            iface_list="$iface_idx_start $(($iface_idx_start + 1))"
            for ii in ${iface_list}; do
                [ "$ii" -eq "$iface_idx_start" ] && {
                    bh_device="wifi0"
                    bh_ifname="`uci get misc.backhauls.backhaul_5g_ap_iface`"
                } || {
                    bh_device="wifi1"
                    bh_ifname="`uci get misc.backhauls.backhaul_2g_ap_iface`"
                }
                uci -q batch <<-EOF >/dev/null
add wireless wifi-iface
set wireless.@wifi-iface[$ii].device="$bh_device"
set wireless.@wifi-iface[$ii].ifname="$bh_ifname"
set wireless.@wifi-iface[$ii].network='lan'
set wireless.@wifi-iface[$ii].mode='ap'
set wireless.@wifi-iface[$ii].ssid="$bh_ssid"
set wireless.@wifi-iface[$ii].encryption="$bh_mgmt"
set wireless.@wifi-iface[$ii].key="$bh_pswd"
set wireless.@wifi-iface[$ii].hidden='1'
set wireless.@wifi-iface[$ii].backhaul='1'
set wireless.@wifi-iface[$ii].backhaul_ap='1'
set wireless.@wifi-iface[$ii].wds='1'
set wireless.@wifi-iface[$ii].wps_pbc='1'
set wireless.@wifi-iface[$ii].wps_pbc_enable='0'
set wireless.@wifi-iface[$ii].wps_pbc_start_time='0'
set wireless.@wifi-iface[$ii].wps_pbc_duration='120'
set wireless.@wifi-iface[$ii].wsplcd_unmanaged='1'
set wireless.@wifi-iface[$ii].repacd_security_unmanaged='1'
set wireless.@wifi-iface[$ii].group='0'
EOF
                local mac_list
                [ "$ii" -eq "$iface_idx_start" ] && {
                    uci -q set wireless.@wifi-iface[$ii].channel_block_list='52,56,60,64'
                    __check_bh_vap_mac_list "5" mac_list
                } || __check_bh_vap_mac_list "2" mac_list
                [ -n "$mac_list" ] && {
                    mac_list="`echo $mac_list | sed "s/,/ /g"`"
                    uci -q set wireless.@wifi-iface[$ii].macfilter='allow'
                    uci -q delete wireless.@wifi-iface[$ii].maclist
                    for mac in $mac_list; do
                        uci -q add_list wireless.@wifi-iface[$ii].maclist="$mac"
                    done
                }
            done
        ;;
    esac

    # set bsd
    [ "$bsd" -eq 1 ] && {
        uci -q set wireless.@wifi-iface[0].bsd='1'
        uci -q set wireless.@wifi-iface[1].bsd='1'
    }
    uci -q set wireless.@wifi-iface[0].miwifi_mesh='0'

    uci -q set wireless.wifi0.repacd_auto_create_vaps=0
	uci -q set wireless.wifi0.CSwOpts='0x31'
    uci -q delete wireless.wifi0.whc_uninit
    uci -q set wireless.wifi1.repacd_auto_create_vaps=0
    uci -q delete wireless.wifi1.whc_uninit
    [ "$WIFI2_EXIST" = "1" ] && {
        uci -q set wireless.wifi2.repacd_auto_create_vaps=0
        uci -q delete wireless.wifi2.whc_uninit
    }

    if [ "$XQWHC_DEBUG" = "1" ]; then
        if [ "$XQWHC_DEBUG_EVT" = "1" ]; then
            uci -q set wireless.wifi0.macaddr="$mac_5g_stub"
            uci -q set wireless.wifi1.macaddr="$mac_2g_stub"
        fi
        #uci -q set wireless.wifi0.channel='149'
        #uci -q set wireless.wifi1.channel='11'

        #uci -q set wireless.wifi0.txpwr=mid
        #uci -q set wireless.wifi1.txpwr=min
    fi

    # restore guest vap cfg
    [ -n "$opts" ] && {
        while read line
        do
            echo "$line" | grep -q "wifi-iface"
            [ $? -eq 0 ] && {
                uci -q set "$line"
                continue
            }
            opt="`echo $line | awk -F "[.=]" '{print $3}'`"
            value="`echo $line | awk -F "'" '{print $2}'`"
            uci -q set wireless.${sguest}.${opt}="${value}"
        done < ${guest_cfg}
    }
    # check guest vap iface
    if uci -q get wireless.${sguest} >/dev/null 2>&1; then
        uci -q set wireless.${sguest}.wsplcd_unmanaged='1'
        uci -q set wireless.${sguest}.repacd_security_unmanaged='1'
    fi

    uci commit wireless
}


# check if ssid & encryption & key changed
# 1: wifi cfg changed
# 0: wifi cfg NO change
__check_wifi_cfg_no_changed()
{
    local key word word_cur
    local ssid_5g_cur="`uci -q get wireless.@wifi-iface[0].ssid`"
    local mgmt_5g_cur="`uci -q get wireless.@wifi-iface[0].encryption`"
    local pswd_5g_cur="`uci -q get wireless.@wifi-iface[0].key`"
    local ssid_2g_cur="`uci -q get wireless.@wifi-iface[1].ssid`"
    local mgmt_2g_cur="`uci -q get wireless.@wifi-iface[1].encryption`"
    local pswd_2g_cur="`uci -q get wireless.@wifi-iface[1].key`"
    local key_lists="ssid_5g mgmt_5g pswd_5g ssid_2g mgmt_2g pswd_2g"
    for key in $key_lists; do
        if [ "$bsd" -eq 0 ]; then
            word="`eval echo '$'"$key"`"
        else
            word="`eval echo '$'"whc_${key:0:4}"`"
        fi
        word_cur="`eval echo '$'"${key}_cur"`"
        [ "$word" != "$word_cur" ] && {
            WHC_LOGI "      wifi init with cfg changed, [$word_cur]->[$word]"
            WHC_LOGI "      [$ssid_5g_cur][$mgmt_5g_cur][$pswd_5g_cur][$ssid_2g_cur][$mgmt_2g_cur][$pswd_2g_cur]->"
            [ "$bsd" -eq 0 ] && {
                WHC_LOGI "      [$ssid_5g][$mgmt_5g][$pswd_5g][$ssid_2g][$mgmt_2g][$pswd_2g]"
            } || {
                WHC_LOGI "      [$whc_ssid][$whc_mgmt][$whc_pswd]"
            }
            return 1
        }
    done

    return 0
}


## check if wifi has config backhaul
# 2 : uninit
# 1: init and wifi cfg change (ssid + key)
# 0: init and wifi cfg NO change
export WIFI_UNINIT=2
export WIFI_INIT_CHANGE=1   #init change need a restore
export WIFI_INIT_NOCHANGE=0
__if_wifi_cfg()
{
    ## uninit
    uci -q get wireless.wifi1.whc_uninit && {
        WHC_LOGI "      wifi uninit."
        return $WIFI_UNINIT
    }
    WHC_LOGI "      wifi config had init before"

    # check if ssid & key changed
    #local ssid_cur="`uci -q get wireless.@wifi-iface[1].ssid`"
    #local key_cur="`uci -q get wireless.@wifi-iface[1].key`"
    #if [ "$whc_ssid" = "$ssid_cur" -a "$whc_pswd" = "$key_cur" ]; then
    if __check_wifi_cfg_no_changed; then
        WHC_LOGI "      wifi init with cfg NO change!"
      # check if wifi iface up ok.
      for ii in seq 0 1 2; do
        __check_wifi_vap && {
            WHC_LOGI "      wifi init with cfg NO change + vap up, ignore whole init!"
            return $WIFI_INIT_NOCHANGE
        } || {
            WHC_LOGI "      wifi init with cfg NO change, but vap not up done, need restore!"
            return $WIFI_INIT_CHANGE
        }
      done
    fi

    #WHC_LOGI "      wifi init with cfg changed, [$ssid_cur][$key_cur]->[$whc_ssid][$whc_pswd]"
    return $WIFI_INIT_CHANGE
}

__delete_admin()
{
    nvram unset nv_sys_pwd
    nvram commit
}

# only call before next cap/re retry, thus we can save wifi up time
xqwhc_preinit()
{
    local role="$1"
    WHC_LOGI "*preinit"

    # terminate xqwhc_superv rtmetric
    ps -w | grep xqwhc | grep -v grep | grep -wq xqwhc_superv && /etc/init.d/xqwhc stop

    # delete former metric buff
    xqwhc_metric_flush

    ps -w | grep -w wifi | grep -v grep | grep -v hostapd | awk '{print $1}' | xargs  kill -9
    __if_wifi_cfg
    ret=$?
    if [ $ret -eq $WIFI_INIT_NOCHANGE ]; then
        if [ "$role" = "cap" -o "$role" = "CAP" ]; then
            [ "`uci -q get xiaoqiang.common.NETMODE`" = "whc_cap" ] || ret=$WIFI_INIT_CHANGE
        fi
    fi
    WHC_LOGI "  preinit, wifi restore & reset, if need? ret=$ret"
    if [ $ret -eq $WIFI_UNINIT ]; then
        # totally un init state
        :
    else
        if [ "$ret" -ne "$WIFI_INIT_NOCHANGE" ]; then
            #__delete_wifi
            __delete_son
            #__delete_admin
        fi

        ## work around for init error netifd brctl error!
        [ `brctl show br-lan | awk 'END{print NR}'` -le 2 ] && {
            WHC_LOGE "**** exception, bridge error; show > `brctl show` ****** "
            /etc/init.d/network restart # incase bridge NOT create
        }
    fi

    WHC_LOGI "*preinit done, ret=$ret"
    return $ret
    
}

____delete_sta_iface()
{
    local config="$1"
    local net="$2"
    local del=0
    config_get netcur "$config" 'network'
    config_get mode "$config" 'mode'

WHC_LOGI " @@@@@@ config $config, network $netcur, mode $mode"
    if [ -z "$mode"  -o -z "$netcur" ]; then
        WHC_LOGI " wifi-iface is invalid, delete "
        del=1
    fi
    if [ "$net" = "$netcur" -a "$mode" = "sta" ]; then
        WHC_LOGI " wifi has init, delete all stas"
        del=1
    fi
    [ "$del" -gt 0 ] && {
        uci -q delete wireless.$config
        uci commit wireless
    }
}

## son network cfg init on RE
__init_network_re()
{
    WHC_LOGI " setup network cfg on $whc_role "

    uci -q set dhcp.lan.ignore=1
    uci commit dhcp
    # until whc init, we add if to bridge
    uci -q set network.lan.ifname='eth1 eth2 eth3 eth4';
    uci -q set network.lan.proto=dhcp
    uci -q delete network.lan.ipaddr
    uci -q delete network.lan.netmask
    uci -q delete network.lan.gateway
    uci -q delete network.lan.dns
    uci -q delete network.lan.mtu

    [ -f "$nw_cfg" ] && {
        local ip="`cat $nw_cfg | awk -F ':' '/ip/{print $2}'`"
        [ -n "$ip" ] && {
            local subnet="`cat $nw_cfg | awk -F ':' '/subnet/{print $2}'`"
            local dns="`cat $nw_cfg | awk -F ':' '/dns/{print $2}'`"
            local router="`cat $nw_cfg | awk -F ':' '/router/{print $2}'`"
            local hostname="`cat $nw_cfg | awk -F ':' '/ap_hostname/{print $2}'`"
            local vendorinfo="`cat $nw_cfg | awk -F ':' '/vendorinfo/{print $2}'`"
            local netmask="${subnet:-255.255.255.0}"
            local mtu="${mtu:-1500}"
            dns="${dns:-$router}"
            #local model=$(uci -q get misc.hardware.model)
            #[ -z "$model" ] && model=$(cat /proc/xiaoqiang/model)
            #local hostname="MiWiFi-$model"
            WHC_LOGI " @@@@@@ ============ mesh re set ip=$ip gw=$router."

            uci -q set xiaoqiang.common.ap_hostname=$hostname
            uci -q set xiaoqiang.common.vendorinfo=$vendorinfo
            uci commit xiaoqiang
            uci -q set network.lan=interface
            uci -q set network.lan.type=bridge
            uci -q set network.lan.proto=static
            uci -q set network.lan.ipaddr=$ip
            uci -q set network.lan.netmask=$netmask
            uci -q set network.lan.gateway=$router
            uci -q set network.lan.mtu=$mtu
            uci -q del network.lan.dns
            uci -q del network.vpn
            for d in $dns
            do
                uci -q add_list network.lan.dns=$d
            done
        }
    }

    # 20200306: no wan on son re, so delete wan
    uci -q delete network.wan
    uci -q delete network.wan6
    uci commit network

    ifdown vpn 2>/dev/null
    /usr/sbin/vasinfo_fw.sh off 2>/dev/null
    [ -f /etc/init.d/hwnat ] && /etc/init.d/hwnat off 2>/dev/null
    /etc/init.d/trafficd stop

    # launch a fast reload network trigger bridge change, without wifi
    kill -SIGUSR1 `pidof udhcpc | xargs` 2>/dev/null    # workaround for lan.ipaddr in multiple init situation
    [ ! -f "$nw_cfg" ] && {
        /etc/init.d/network reload_fast
        #/etc/init.d/network reload
        /etc/init.d/dnsmasq restart
    }
}

## son wireless cfg init on RE
__init_wifi_re()
{
    WHC_LOGI " setup wifi cfg on $whc_role "

    # wifi, do NOT auto create wifi vap by repacd, setup vap and key parameters by user define
    uci -q set wireless.wifi0.repacd_auto_create_vaps=0
    uci -q set wireless.wifi0.CSwOpts='0x31'
    uci -q delete wireless.wifi0.whc_uninit
    uci -q set wireless.wifi1.repacd_auto_create_vaps=0
    uci -q delete wireless.wifi1.whc_uninit
    ifconfig wifi2 >/dev/null 2>&1 && export WIFI2_EXIST=1 || export WIFI2_EXIST=0
    [ "$WIFI2_EXIST" = "1" ] && {
        uci -q set wireless.wifi2.repacd_auto_create_vaps=0
        uci -q delete wireless.wifi2.whc_uninit
    }

    if [ "$XQWHC_DEBUG_EVT" = "1" ]; then
        uci -q set wireless.wifi0.macaddr="$mac_2g_stub"
        uci -q set wireless.wifi1.macaddr="$mac_5g_stub"

        #uci -q set wireless.wifi0.txpwr=mid
        #uci -q set wireless.wifi1.txpwr=min
    fi

    local iface_list="" ii=0 idx=0 iface_idx_start=2
    local main_ssid main_mgmt main_pswd
    [ "$WIFI2_EXIST" = "1" ] && iface_idx_start=3 || iface_idx_start=2
    case "$BH_METHOD" in
        $USE_DUAL_BAND_BH)
            # config wifi ap ifaces
            iface_list="0 1"
            for ii in ${iface_list}; do
                if [ "$bsd" -eq 0 ]; then
                    [ "$ii" -eq 0 ] && {
                        main_ssid=$ssid_5g
                        main_mgmt=$mgmt_5g
                        main_pswd=$pswd_5g
                    } || {
                        main_ssid=$ssid_2g
                        main_mgmt=$mgmt_2g
                        main_pswd=$pswd_2g
                    }
                else
                    main_ssid=$whc_ssid
                    main_mgmt=$whc_mgmt
                    main_pswd=$whc_pswd
                fi
                uci -q batch <<-EOF >/dev/null
set wireless.@wifi-iface[$ii].ssid="$main_ssid"
set wireless.@wifi-iface[$ii].encryption="$main_mgmt"
set wireless.@wifi-iface[$ii].key="$main_pswd"
set wireless.@wifi-iface[$ii].backhaul='1'
set wireless.@wifi-iface[$ii].backhaul_ap='1'
set wireless.@wifi-iface[$ii].wnm='1'
set wireless.@wifi-iface[$ii].wds='1'
set wireless.@wifi-iface[$ii].rrm='1'
set wireless.@wifi-iface[$ii].wps_pbc='1'
set wireless.@wifi-iface[$ii].wps_pbc_enable='0'
set wireless.@wifi-iface[$ii].wps_pbc_start_time='0'
set wireless.@wifi-iface[$ii].wps_pbc_duration='120'
set wireless.@wifi-iface[$ii].group='0'
set wireless.@wifi-iface[$ii].blockdfschan='0'
set wireless.@wifi-iface[$ii].disablecoext='0'
EOF
                case "$main_mgmt" in
                    none)
                        uci -q delete wireless.@wifi-iface[$ii].key
                    ;;
                    mixed-psk|psk2)
                    ;;
                    psk2+ccmp)
                        uci -q set wireless.@wifi-iface[$ii].sae='1'
                        uci -q set wireless.@wifi-iface[$ii].sae_password="$main_pswd"
                        uci -q set wireless.@wifi-iface[$ii].ieee80211w='1'
                    ;;
                    ccmp)
                        uci -q delete wireless.@wifi-iface[$ii].key
                        uci -q set wireless.@wifi-iface[$ii].sae='1'
                        uci -q set wireless.@wifi-iface[$ii].sae_password="$main_pswd"
                        uci -q set wireless.@wifi-iface[$ii].ieee80211w='2'
                    ;;
                esac
            done
#cfg repacd not add default
:<<!
uci set wireless.@wifi-iface[$ii].backhaul='1'
uci set wireless.@wifi-iface[$ii].wnm='1'
uci set wireless.@wifi-iface[$ii].group='0'
!

            # setup dual band bh sta ifaces
            iface_list="$iface_idx_start $(($iface_idx_start + 1))"
            for ii in ${iface_list}; do
                idx=$(($ii % $iface_idx_start))
                if [ "$bsd" -eq 0 ]; then
                    [ "$idx" -eq 0 ] && {
                        main_ssid=$ssid_5g
                        main_mgmt=$mgmt_5g
                        main_pswd=$pswd_5g
                    } || {
                        main_ssid=$ssid_2g
                        main_mgmt=$mgmt_2g
                        main_pswd=$pswd_2g
                    }
                else
                    main_ssid=$whc_ssid
                    main_mgmt=$whc_mgmt
                    main_pswd=$whc_pswd
                fi
                uci -q batch <<-EOF >/dev/null
add wireless wifi-iface
set wireless.@wifi-iface[$ii]=wifi-iface
set wireless.@wifi-iface[$ii].device="wifi$idx"
set wireless.@wifi-iface[$ii].ifname="wl"$idx"1"
set wireless.@wifi-iface[$ii].network='lan'
set wireless.@wifi-iface[$ii].mode='sta'
set wireless.@wifi-iface[$ii].ssid="$main_ssid"
set wireless.@wifi-iface[$ii].encryption="$main_mgmt"
set wireless.@wifi-iface[$ii].key="$main_pswd"
set wireless.@wifi-iface[$ii].wds='1'
set wireless.@wifi-iface[$ii].wps_pbc='1'
set wireless.@wifi-iface[$ii].wps_pbc_enable='0'
set wireless.@wifi-iface[$ii].wps_pbc_start_time='0'
set wireless.@wifi-iface[$ii].wps_pbc_duration='120'
set wireless.@wifi-iface[$ii].disabled='0'
set wireless.@wifi-iface[$ii].backhaul='1'
set wireless.@wifi-iface[$ii].group='0'
EOF
                case "$main_mgmt" in
                    none)
                        uci -q delete wireless.@wifi-iface[$ii].key
                    ;;
                    mixed-psk|psk2)
                    ;;
                    psk2+ccmp)
                        uci -q set wireless.@wifi-iface[$ii].sae='1'
                        uci -q set wireless.@wifi-iface[$ii].sae_password="$main_pswd"
                        uci -q set wireless.@wifi-iface[$ii].ieee80211w='1'
                    ;;
                    ccmp)
                        uci -q delete wireless.@wifi-iface[$ii].key
                        uci -q set wireless.@wifi-iface[$ii].sae='1'
                        uci -q set wireless.@wifi-iface[$ii].sae_password="$main_pswd"
                        uci -q set wireless.@wifi-iface[$ii].ieee80211w='2'
                    ;;
                esac
            done
#cfg repacd not add default
:<<!
uci set wireless.@wifi-iface[3/4].backhaul='1'
uci set wireless.@wifi-iface[3/4].group='0'
!
        ;;
        $USE_ONLY_5G_BH)
            # config wifi ap ifaces
            iface_list="0 1"
            for ii in ${iface_list}; do
                if [ "$bsd" -eq 0 ]; then
                    [ "$ii" -eq 0 ] && {
                        main_ssid=$ssid_5g
                        main_mgmt=$mgmt_5g
                        main_pswd=$pswd_5g
                    } || {
                        main_ssid=$ssid_2g
                        main_mgmt=$mgmt_2g
                        main_pswd=$pswd_2g
                    }
                else
                    main_ssid=$whc_ssid
                    main_mgmt=$whc_mgmt
                    main_pswd=$whc_pswd
                fi
                uci -q batch <<-EOF >/dev/null
set wireless.@wifi-iface[$ii].ssid="$main_ssid"
set wireless.@wifi-iface[$ii].encryption="$main_mgmt"
set wireless.@wifi-iface[$ii].key="$main_pswd"
set wireless.@wifi-iface[$ii].wnm='1'
set wireless.@wifi-iface[$ii].rrm='1'
set wireless.@wifi-iface[$ii].wsplcd_unmanaged='1'
set wireless.@wifi-iface[$ii].repacd_security_unmanaged='1'
EOF
                case "$main_mgmt" in
                    none)
                        uci -q delete wireless.@wifi-iface[$ii].key
                    ;;
                    mixed-psk|psk2)
                    ;;
                    psk2+ccmp)
                        uci -q set wireless.@wifi-iface[$ii].sae='1'
                        uci -q set wireless.@wifi-iface[$ii].sae_password="$main_pswd"
                        uci -q set wireless.@wifi-iface[$ii].ieee80211w='1'
                    ;;
                    ccmp)
                        uci -q delete wireless.@wifi-iface[$ii].key
                        uci -q set wireless.@wifi-iface[$ii].sae='1'
                        uci -q set wireless.@wifi-iface[$ii].sae_password="$main_pswd"
                        uci -q set wireless.@wifi-iface[$ii].ieee80211w='2'
                    ;;
                esac
            done
            uci -q set wireless.@wifi-iface[0].backhaul='1'
            uci -q set wireless.@wifi-iface[0].backhaul_ap='1'
            uci -q set wireless.@wifi-iface[0].wds='1'
            uci -q set wireless.@wifi-iface[0].wps_pbc='1'
            uci -q set wireless.@wifi-iface[0].wps_pbc_enable='0'
            uci -q set wireless.@wifi-iface[0].wps_pbc_start_time='0'
            uci -q set wireless.@wifi-iface[0].wps_pbc_duration='120'
            uci -q set wireless.@wifi-iface[0].group='0'
            uci -q set wireless.@wifi-iface[0].blockdfschan='0'
            uci -q set wireless.@wifi-iface[0].disablecoext='0'

            # setup 5G ind bh sta ifaces
            iface_list="$iface_idx_start"
            for ii in ${iface_list}; do
                idx=$(($ii % $iface_idx_start))
                if [ "$bsd" -eq 0 ]; then
                    main_ssid=$ssid_5g
                    main_mgmt=$mgmt_5g
                    main_pswd=$pswd_5g
                else
                    main_ssid=$whc_ssid
                    main_mgmt=$whc_mgmt
                    main_pswd=$whc_pswd
                fi
                uci -q batch <<-EOF >/dev/null
add wireless wifi-iface
set wireless.@wifi-iface[$ii]=wifi-iface
set wireless.@wifi-iface[$ii].device="wifi$idx"
set wireless.@wifi-iface[$ii].ifname="wl"$idx"1"
set wireless.@wifi-iface[$ii].network='lan'
set wireless.@wifi-iface[$ii].mode='sta'
set wireless.@wifi-iface[$ii].ssid="$main_ssid"
set wireless.@wifi-iface[$ii].encryption="$main_mgmt"
set wireless.@wifi-iface[$ii].key="$main_pswd"
set wireless.@wifi-iface[$ii].wds='1'
set wireless.@wifi-iface[$ii].wps_pbc='1'
set wireless.@wifi-iface[$ii].wps_pbc_enable='0'
set wireless.@wifi-iface[$ii].wps_pbc_start_time='0'
set wireless.@wifi-iface[$ii].wps_pbc_duration='120'
set wireless.@wifi-iface[$ii].disabled='0'
set wireless.@wifi-iface[$ii].backhaul='1'
set wireless.@wifi-iface[$ii].group='0'
set wireless.@wifi-iface[$ii].wsplcd_unmanaged='1'
set wireless.@wifi-iface[$ii].repacd_security_unmanaged='1'
EOF
                case "$main_mgmt" in
                    none)
                        uci -q delete wireless.@wifi-iface[$ii].key
                    ;;
                    mixed-psk|psk2)
                    ;;
                    psk2+ccmp)
                        uci -q set wireless.@wifi-iface[$ii].sae='1'
                        uci -q set wireless.@wifi-iface[$ii].sae_password="$main_pswd"
                        uci -q set wireless.@wifi-iface[$ii].ieee80211w='1'
                    ;;
                    ccmp)
                        uci -q delete wireless.@wifi-iface[$ii].key
                        uci -q set wireless.@wifi-iface[$ii].sae='1'
                        uci -q set wireless.@wifi-iface[$ii].sae_password="$main_pswd"
                        uci -q set wireless.@wifi-iface[$ii].ieee80211w='2'
                    ;;
                esac
                uci -q delete wireless.@wifi-iface[$ii].bssid
            done
        ;;
        $USE_ONLY_5G_IND_VAP_BH)
            # config wifi ap ifaces
            iface_list="0 1"
            for ii in ${iface_list}; do
                if [ "$bsd" -eq 0 ]; then
                    [ "$ii" -eq 0 ] && {
                        main_ssid=$ssid_5g
                        main_mgmt=$mgmt_5g
                        main_pswd=$pswd_5g
                    } || {
                        main_ssid=$ssid_2g
                        main_mgmt=$mgmt_2g
                        main_pswd=$pswd_2g
                    }
                else
                    main_ssid=$whc_ssid
                    main_mgmt=$whc_mgmt
                    main_pswd=$whc_pswd
                fi
                uci -q set wireless.@wifi-iface[$ii].ssid="$main_ssid"
                uci -q set wireless.@wifi-iface[$ii].encryption="$main_mgmt"
                uci -q set wireless.@wifi-iface[$ii].key="$main_pswd"
                uci -q batch <<-EOF >/dev/null
set wireless.@wifi-iface[$ii].wnm='1'
set wireless.@wifi-iface[$ii].rrm='1'
set wireless.@wifi-iface[$ii].wsplcd_unmanaged='1'
set wireless.@wifi-iface[$ii].repacd_security_unmanaged='1'
EOF
                case "$main_mgmt" in
                    none)
                        uci -q delete wireless.@wifi-iface[$ii].key
                    ;;
                    mixed-psk|psk2)
                    ;;
                    psk2+ccmp)
                        uci -q set wireless.@wifi-iface[$ii].sae='1'
                        uci -q set wireless.@wifi-iface[$ii].sae_password="$main_pswd"
                        uci -q set wireless.@wifi-iface[$ii].ieee80211w='1'
                    ;;
                    ccmp)
                        uci -q delete wireless.@wifi-iface[$ii].key
                        uci -q set wireless.@wifi-iface[$ii].sae='1'
                        uci -q set wireless.@wifi-iface[$ii].sae_password="$main_pswd"
                        uci -q set wireless.@wifi-iface[$ii].ieee80211w='2'
                    ;;
                esac
            done

:<<!
            local mac_b5=$(echo $whc_mac | cut -d ':' -f 5)
            local mac_b6=$(echo $whc_mac | cut -d ':' -f 6)
            local uid=$(printf "%04X" $((0x$mac_b5$mac_b6)))
            local bh_ssid="${BHPREFIX}_${uid}"
            local bh_mgmt="$bh_defmgmt"
            local bh_passwd="$(xor_sum "$bh_ssid" "$whc_mac")"
!
            # setup 5G ind bh sta ifaces
            iface_list="$iface_idx_start"
            for ii in ${iface_list}; do
                idx=$(($ii % $iface_idx_start))
                uci -q batch <<-EOF >/dev/null
add wireless wifi-iface
set wireless.@wifi-iface[$ii]=wifi-iface
set wireless.@wifi-iface[$ii].device="wifi$idx"
set wireless.@wifi-iface[$ii].ifname="wl"$idx"1"
set wireless.@wifi-iface[$ii].network='lan'
set wireless.@wifi-iface[$ii].mode='sta'
set wireless.@wifi-iface[$ii].ssid="$bh_ssid"
set wireless.@wifi-iface[$ii].encryption="$bh_mgmt"
set wireless.@wifi-iface[$ii].key="$bh_pswd"
set wireless.@wifi-iface[$ii].wds='1'
set wireless.@wifi-iface[$ii].wps_pbc='1'
set wireless.@wifi-iface[$ii].wps_pbc_enable='0'
set wireless.@wifi-iface[$ii].wps_pbc_start_time='0'
set wireless.@wifi-iface[$ii].wps_pbc_duration='120'
set wireless.@wifi-iface[$ii].disabled='0'
set wireless.@wifi-iface[$ii].backhaul='1'
set wireless.@wifi-iface[$ii].group='0'
set wireless.@wifi-iface[$ii].wsplcd_unmanaged='1'
set wireless.@wifi-iface[$ii].repacd_security_unmanaged='1'
EOF
            done

            # setup 5G ind bh ap ifaces
            ii=$(($iface_idx_start + 1))
            local bh_ifname="`uci get misc.backhauls.backhaul_5g_ap_iface`"
            uci -q batch <<-EOF >/dev/null
add wireless wifi-iface
set wireless.@wifi-iface[$ii].device='wifi0'
set wireless.@wifi-iface[$ii].ifname="$bh_ifname"
set wireless.@wifi-iface[$ii].network='lan'
set wireless.@wifi-iface[$ii].mode='ap'
set wireless.@wifi-iface[$ii].channel_block_list='52,56,60,64'
set wireless.@wifi-iface[$ii].ssid="$bh_ssid"
set wireless.@wifi-iface[$ii].encryption="$bh_mgmt"
set wireless.@wifi-iface[$ii].key="$bh_pswd"
set wireless.@wifi-iface[$ii].hidden='1'
set wireless.@wifi-iface[$ii].backhaul='1'
set wireless.@wifi-iface[$ii].backhaul_ap='1'
set wireless.@wifi-iface[$ii].wds='1'
set wireless.@wifi-iface[$ii].wps_pbc='1'
set wireless.@wifi-iface[$ii].wps_pbc_enable='0'
set wireless.@wifi-iface[$ii].wps_pbc_start_time='0'
set wireless.@wifi-iface[$ii].wps_pbc_duration='120'
set wireless.@wifi-iface[$ii].group='0'
set wireless.@wifi-iface[$ii].wsplcd_unmanaged='1'
set wireless.@wifi-iface[$ii].repacd_security_unmanaged='1'
EOF
            local mac_list
            __check_bh_vap_mac_list "5" mac_list
            # set bh ssid macfilter on re no matter whether mac_list is existed
            uci -q set wireless.@wifi-iface[$ii].macfilter='allow'
            [ -n "$mac_list" ] && {
                mac_list="`echo $mac_list | sed "s/,/ /g"`"
                uci -q set wireless.@wifi-iface[$ii].macfilter='allow'
                uci -q delete wireless.@wifi-iface[$ii].maclist
                for mac in $mac_list; do
                    uci -q add_list wireless.@wifi-iface[$ii].maclist="$mac"
                done
            }
        ;;
        # default USE_DUAL_BAND_IND_VAP_BH
        $USE_DUAL_BAND_IND_VAP_BH | *)
            # config wifi ap ifaces
            iface_list="0 1"
            for ii in ${iface_list}; do
                if [ "$bsd" -eq 0 ]; then
                    [ "$ii" -eq 0 ] && {
                        main_ssid=$ssid_5g
                        main_mgmt=$mgmt_5g
                        main_pswd=$pswd_5g
                    } || {
                        main_ssid=$ssid_2g
                        main_mgmt=$mgmt_2g
                        main_pswd=$pswd_2g
                    }
                else
                    main_ssid=$whc_ssid
                    main_mgmt=$whc_mgmt
                    main_pswd=$whc_pswd
                fi
                uci -q set wireless.@wifi-iface[$ii].ssid="$main_ssid"
                uci -q set wireless.@wifi-iface[$ii].encryption="$main_mgmt"
                uci -q set wireless.@wifi-iface[$ii].key="$main_pswd"
                uci -q batch <<-EOF >/dev/null
set wireless.@wifi-iface[$ii].wnm='1'
set wireless.@wifi-iface[$ii].rrm='1'
set wireless.@wifi-iface[$ii].wsplcd_unmanaged='1'
set wireless.@wifi-iface[$ii].repacd_security_unmanaged='1'
EOF
                case "$main_mgmt" in
                    none)
                        uci -q delete wireless.@wifi-iface[$ii].key
                    ;;
                    mixed-psk|psk2)
                    ;;
                    psk2+ccmp)
                        uci -q set wireless.@wifi-iface[$ii].sae='1'
                        uci -q set wireless.@wifi-iface[$ii].sae_password="$main_pswd"
                        uci -q set wireless.@wifi-iface[$ii].ieee80211w='1'
                    ;;
                    ccmp)
                        uci -q delete wireless.@wifi-iface[$ii].key
                        uci -q set wireless.@wifi-iface[$ii].sae='1'
                        uci -q set wireless.@wifi-iface[$ii].sae_password="$main_pswd"
                        uci -q set wireless.@wifi-iface[$ii].ieee80211w='2'
                    ;;
                esac
            done

            # setup dual band ind bh sta ifaces
            iface_list="$iface_idx_start $(($iface_idx_start + 1))"
            for ii in ${iface_list}; do
                idx=$(($ii % $iface_idx_start))
                uci -q batch <<-EOF >/dev/null
add wireless wifi-iface
set wireless.@wifi-iface[$ii]=wifi-iface
set wireless.@wifi-iface[$ii].device="wifi$idx"
set wireless.@wifi-iface[$ii].ifname="wl"$idx"1"
set wireless.@wifi-iface[$ii].network='lan'
set wireless.@wifi-iface[$ii].mode='sta'
set wireless.@wifi-iface[$ii].ssid="$bh_ssid"
set wireless.@wifi-iface[$ii].encryption="$bh_mgmt"
set wireless.@wifi-iface[$ii].key="$bh_pswd"
set wireless.@wifi-iface[$ii].wds='1'
set wireless.@wifi-iface[$ii].wps_pbc='1'
set wireless.@wifi-iface[$ii].wps_pbc_enable='0'
set wireless.@wifi-iface[$ii].wps_pbc_start_time='0'
set wireless.@wifi-iface[$ii].wps_pbc_duration='120'
set wireless.@wifi-iface[$ii].disabled='0'
set wireless.@wifi-iface[$ii].backhaul='1'
set wireless.@wifi-iface[$ii].group='0'
set wireless.@wifi-iface[$ii].wsplcd_unmanaged='1'
set wireless.@wifi-iface[$ii].repacd_security_unmanaged='1'
EOF
            done

            # setup dual band ind bh ap ifaces
            local bh_device bh_ifname
            iface_list="$(($iface_idx_start + 2)) $(($iface_idx_start + 3))"
            for ii in ${iface_list}; do
                [ "$ii" -eq "$(($iface_idx_start + 2))" ] && {
                    bh_device="wifi0"
                    bh_ifname="`uci get misc.backhauls.backhaul_5g_ap_iface`"
                } || {
                    bh_device="wifi1"
                    bh_ifname="`uci get misc.backhauls.backhaul_2g_ap_iface`"
                }
                uci -q batch <<-EOF >/dev/null
add wireless wifi-iface
set wireless.@wifi-iface[$ii].device="$bh_device"
set wireless.@wifi-iface[$ii].ifname="$bh_ifname"
set wireless.@wifi-iface[$ii].network='lan'
set wireless.@wifi-iface[$ii].mode='ap'
set wireless.@wifi-iface[$ii].ssid="$bh_ssid"
set wireless.@wifi-iface[$ii].encryption="$bh_mgmt"
set wireless.@wifi-iface[$ii].key="$bh_pswd"
set wireless.@wifi-iface[$ii].hidden='1'
set wireless.@wifi-iface[$ii].backhaul='1'
set wireless.@wifi-iface[$ii].backhaul_ap='1'
set wireless.@wifi-iface[$ii].wds='1'
set wireless.@wifi-iface[$ii].wps_pbc='1'
set wireless.@wifi-iface[$ii].wps_pbc_enable='0'
set wireless.@wifi-iface[$ii].wps_pbc_start_time='0'
set wireless.@wifi-iface[$ii].wps_pbc_duration='120'
set wireless.@wifi-iface[$ii].group='0'
set wireless.@wifi-iface[$ii].wsplcd_unmanaged='1'
set wireless.@wifi-iface[$ii].repacd_security_unmanaged='1'
EOF
                local mac_list
                [ "$ii" -eq "$(($iface_idx_start + 2))" ] && {
                    uci -q set wireless.@wifi-iface[$ii].channel_block_list='52,56,60,64'
                    __check_bh_vap_mac_list "5" mac_list
                } || __check_bh_vap_mac_list "2" mac_list
                # set bh ssid macfilter on re no matter whether mac_list is existed
                uci -q set wireless.@wifi-iface[$ii].macfilter='allow'
                [ -n "$mac_list" ] && {
                    mac_list="`echo $mac_list | sed "s/,/ /g"`"
                    uci -q set wireless.@wifi-iface[$ii].macfilter='allow'
                    uci -q delete wireless.@wifi-iface[$ii].maclist
                    for mac in $mac_list; do
                        uci -q add_list wireless.@wifi-iface[$ii].maclist="$mac"
                    done
                }
            done
        ;;
    esac

    # set bsd
    [ "$bsd" -eq 1 ] && {
        uci -q set wireless.@wifi-iface[0].bsd='1'
        uci -q set wireless.@wifi-iface[1].bsd='1'
    }
    uci -q set wireless.@wifi-iface[0].miwifi_mesh='0'

    local sguest="$(uci -q get misc.wireless.iface_guest_2g_name)"
    [ -z "$sguest" ] && sguest=guest_2G
    if uci -q get wireless.${sguest} >/dev/null 2>&1; then
        WHC_LOGI " has guest network, destroy before create whc-RE!"
        guestwifi.sh unset
    fi

    uci commit wireless
}


__init_cap()
{
    WHC_LOGI " __init_cap: continue..."

    __set_xqmode 1 cap

    __init_wifi_cap
    __init_son

    __start_son

    return 0
}

__init_re()
{
    WHC_LOGD " __init_re: continue..."

    __set_xqmode 1 re

    __init_network_re
    __init_wifi_re
    __init_son

    __start_son

    return 0
}

__trigger_wps()
{
    env -i ACTION="pressed" BUTTON="wps" /sbin/hotplug-call button
    return 0
}

__start_mi()
{
    # miwifi service TOBE confirm
    /etc/init.d/xqwhc start &   # here use start to launch xqwhc_superv, NOT kill rtmetric leave it work in early init-done 

    if xqwhc_is_re; then
        (/etc/init.d/firewall stop;/etc/init.d/firewall disable) &
    fi

    if xqwhc_is_cap; then
        # for CAP, led blue on after init
        led_check && gpio_led blue off || gpio_led blue on

        /etc/init.d/firewall restart &
        WHC_LOGI "Device was initted! clear br-port isolate_mode!"
        #echo 0 > /sys/devices/soc.0/c080000.edma/net/eth0/brport/isolate_mode 2>&1
        #echo 0 > /sys/devices/virtual/net/eth2/brport/isolate_mode 2>&1
        #echo 0 > /sys/devices/virtual/net/eth3/brport/isolate_mode 2>&1
        #echo 0 > /sys/devices/virtual/net/eth4/brport/isolate_mode 2>&1
        echo 0 > /sys/devices/virtual/net/wl0/brport/isolate_mode 2>&1
        echo 0 > /sys/devices/virtual/net/wl1/brport/isolate_mode 2>&1
    fi

    /etc/init.d/wan_check restart
    # trafficd move into dhcp_apclient.sh callback
    /etc/init.d/mosquitto restart &
    /etc/init.d/xq_info_sync_mqtt restart &
    /etc/init.d/dnsmasq restart &
    /etc/init.d/xqbc restart &
    /etc/init.d/miqos restart &
    /etc/init.d/xiaoqiang_sync restart &
    /etc/init.d/messagingagent.sh restart &
    
#    /usr/sbin/shareUpdate -b;
#    [ -f /etc/init.d/hwnat ] && /etc/init.d/hwnat restart;
#    [ -f /etc/init.d/plugin_start_script.sh ] && /etc/init.d/plugin_start_script.sh restart;

}

# params="{\"whc_role\":\"RE\",\"whc_ssid\":\"!@Mi-son\",\"whc_pswd\":\"123456789\"}"
# params="{\"whc_role\":\"CAP\",\"whc_ssid\":\"!@Mi-son\",\"whc_pswd\":\"123456789\"}"
# buff="{\"method\":\"init\",\"params\":{\"whc_role\":\"CAP\",\"bsd\":\"0\",\"ssid_2g\":\"!@Mi-son\",\"mgmt_2g\":\"mixed-psk\",\"pswd_2g\":\"123456789\",\"ssid_5g\":\"!@Mi-son_5G\",\"mgmt_5g\":\"mixed-psk\",\"pswd_5g\":\"123456789\"}}"
# buff="{\"method\":\"init\",\"params\":{\"whc_role\":\"CAP\",\"bsd\":\"0\",\"ssid_2g\":\"!@Mi-son\",\"mgmt_2g\":\"mixed-psk\",\"pswd_2g\":\"123456789\",\"ssid_5g\":\"!@Mi-son_5G\",\"mgmt_5g\":\"mixed-psk\",\"pswd_5g\":\"123456789\",\"bh_ssid\":\"MiMesh_A1B2\",\"bh_mgmt\":\"psk2+ccmp\",\"bh_pswd\":\"1234567890\"}}"
xqwhc_init()
{
    #gpio_led l green 600 600 &

    ### get whc keys
    #json_load "$params"
    export bsd=1
    local para_bsd="`json_get_value \"$params\" \"bsd\"`"
    [ "$para_bsd" = "0" ] && bsd=0
    WHC_LOGI " keys:<bsd:$bsd>"
    [ "$bsd" -eq 0 ] && key_list="whc_role ssid_2g mgmt_2g pswd_2g ssid_5g mgmt_5g pswd_5g" || key_list="whc_role whc_ssid whc_pswd whc_mgmt"
    if [ "$BH_METHOD" -eq "$USE_ONLY_5G_IND_VAP_BH" ]; then
        key_list="$key_list bh_ssid bh_mgmt bh_pswd bh_macnum_5g bh_maclist_5g"
    elif [ "$BH_METHOD" -eq "$USE_DUAL_BAND_IND_VAP_BH" ]; then
        key_list="$key_list bh_ssid bh_mgmt bh_pswd bh_macnum_2g bh_maclist_2g bh_macnum_5g bh_maclist_5g"
    fi
    for key in $key_list; do
        #echo $key
        eval "export $key=\"\""
        eval "$key=\"`json_get_value \"$params\" \"$key\"`\""

        [ -z "$key" ] && {
            WHC_LOGE " error whc_init, no $key exist"
            message="\" error whc_init, no $key exist\""
            return $ERR_PARAM_NON
        }
    done

    if [ "$bsd" -eq 0 ]; then
        [ -z "$ssid_2g" ] && ssid_2g="!@Mi-son" || ssid_2g="`printf \"%s\" \"$ssid_2g\" | base64 -d`"
        [ -z "$mgmt_2g" ] && mgmt_2g="mixed-psk"
        [ -z "$pswd_2g" ] && mgmt_2g="none" || pswd_2g="`printf \"%s\" \"$pswd_2g\" | base64 -d`"
        [ -z "$ssid_5g" ] && ssid_5g="!@Mi-son_5G" || ssid_5g="`printf \"%s\" \"$ssid_5g\" | base64 -d`"
        [ -z "$mgmt_5g" ] && mgmt_5g="mixed-psk"
        [ -z "$pswd_5g" ] && mgmt_5g="none" || pswd_5g="`printf \"%s\" \"$pswd_5g\" | base64 -d`"
        if [ "$BH_METHOD" -eq "$USE_ONLY_5G_IND_VAP_BH" -o "$BH_METHOD" -eq "$USE_DUAL_BAND_IND_VAP_BH" ]; then
            [ -z "$bh_ssid" ] && bh_ssid_5g="MiMesh_A1B2"
            [ -z "$bh_mgmt" ] && bh_mgmt_5g="psk2+ccmp"
            [ -z "$bh_pswd" ] && bh_mgmt_5g="none"
            [ -z "$bh_macnum_2g" -o "$bh_macnum_2g" -eq 0 ] && bh_maclist_2g=""
            [ -z "$bh_macnum_5g" -o "$bh_macnum_5g" -eq 0 ] && bh_maclist_5g=""
            WHC_LOGI " keys:<$whc_role>,<$bsd>,<$ssid_2g>,<$pswd_2g>,<$mgmt_2g>,<$ssid_5g>,<$pswd_5g>,<$mgmt_5g>,<$bh_ssid>,<$bh_pswd>,<$bh_mgmt>"
            WHC_LOGI " keys:<$bh_macnum_2g>,<$bh_maclist_2g>,<$bh_macnum_5g>,<$bh_maclist_5g>"
        else
            WHC_LOGI " keys:<$whc_role>,<$bsd>,<$ssid_2g>,<$pswd_2g>,<$mgmt_2g>,<$ssid_5g>,<$pswd_5g>,<$mgmt_5g>"
        fi
    else
        [ -z "$whc_ssid" ] && whc_ssid="!@Mi-son" || whc_ssid="`printf \"%s\" \"$whc_ssid\" | base64 -d`"
        [ -z "$whc_mgmt" ] && whc_mgmt="mixed-psk"
        [ -z "$whc_pswd" ] && whc_mgmt="none" || whc_pswd="`printf \"%s\" \"$whc_pswd\" | base64 -d`"
        if [ "$BH_METHOD" -eq "$USE_ONLY_5G_IND_VAP_BH" -o "$BH_METHOD" -eq "$USE_DUAL_BAND_IND_VAP_BH" ]; then
            [ -z "$bh_ssid" ] && bh_ssid_5g="MiMesh_A1B2"
            [ -z "$bh_mgmt" ] && bh_mgmt_5g="psk2"
            [ -z "$bh_pswd" ] && bh_mgmt_5g="none"
            [ -z "$bh_macnum_2g" -o "$bh_macnum_2g" -eq 0 ] && bh_maclist_2g=""
            [ -z "$bh_macnum_5g" -o "$bh_macnum_5g" -eq 0 ] && bh_maclist_5g=""
            WHC_LOGI " keys:<$whc_role>,<$bsd>,<$whc_ssid>,<$whc_pswd>,<$whc_mgmt>,<$bh_ssid>,<$bh_pswd>,<$bh_mgmt>"
            WHC_LOGI " keys:<$bh_macnum_2g>,<$bh_maclist_2g>,<$bh_macnum_5g>,<$bh_maclist_5g>"
        else
            WHC_LOGI " keys:<$whc_role>,<$bsd>,<$whc_ssid>,<$whc_pswd>,<$whc_mgmt>"
        fi
    fi

    # stub debug to get wifi_mac
    if [ "$XQWHC_DEBUG_EVT" = "1" ]; then
        mac_base=`getmac lan | sed 's/://g'`
        # trasfer from F0B42941EF54 to F0:B4:29:41:EF:54
        format_mac()
        {
            str=""
            for i in `seq 1 2 11`; do
                byte=`echo "$1" | cut -b $i-$((i+1))`
                str="${str}:${byte}"
            done

            str=`echo $str | sed 's/^://' | sed 'y/abcdef/ABCDEF/'`
            echo $str
        }
        mac_2g_stub=$(format_mac `printf %012x $((0x$mac_base + 1))`)
        mac_5g_stub=$(format_mac `printf %012x $((0x$mac_base + 2))`)
    fi

    case "$whc_role" in
        cap|CAP)
            # check if wireless is not default, then recreate it for a safe multi calling
            xqwhc_preinit "$whc_role"
            ret=$?
            [ $ret -eq $WIFI_INIT_NOCHANGE ] || {
                __init_cap
                ret=$?
            }

            ;;

        re|RE)
            # check if wireless is not default, then recreate it for a safe multi calling
            xqwhc_preinit "$whc_role"
            ret=$?
            [ $ret -eq $WIFI_INIT_NOCHANGE ] || {
                __init_re
                ret=$?
            }

            # add a short span to update linkmetric in realtime
            xqwhc_superv rtmetric &
            ;;
        *)
            WHC_LOGE " invalid role $whc_role"
            message="\" error whc_init, invalid role $whc_role\""
            ret=$ERR_PARAM_INV
            ;;
    esac

    [ "$ret" -ne 0 ] && {
        WHC_LOGE "    init $whc_role error!"
        #gpio_led l yellow 1000 1000 &
    }

    WHC_LOGI " --- "
    return 0
}

xqwhc_delete()
{
    local role=$(xqwhc_get_stat)

    # restore xq NETMODE
    __set_xqmode 0

    __delete_son

    __delete_wifi

    __delete_admin

    # network restore on RE
    [ "$role" = "RE" ] && {
        uci -q set dhcp.lan.ignore=0
        uci commit dhcp

        uci -q set network.lan.proto=static
        uci -q set network.lan.ipaddr=192.168.31.1
        uci -q set network.lan.netmask=255.255.255.0
        uci -q delete network.lan.gateway
        uci -q delete network.lan.dns
        uci -q delete network.lan.mtu

        # 20180716: wan section handle by autowan module, so ignore in son
        #uci -q delete network.wan
        #uci -q set network.wan=interface
        #uci -q set network.wan.ifname='eth0'
        #uci -q set network.wan.proto=dhcp

        uci commit network
        /etc/init.d/firewall enable
    }

    # led reset to uninit
    gpio_led l yellow 1000 1000 &

    sync
    /etc/init.d/network restart
    [ -f /etc/init.d/mcsd ] && /etc/init.d/mcsd restart
    # /etc/init.d/firewall restart   # firewall should restart by hotplug
    # mi service restart move to udhcpc callback
    __start_mi


    #nvram set restore_defaults=1
    #nvram commit
    #(sleep 2; reboot) &
    return 0
}

# handle miwifi service
xqwhc_postinit()
{
    WHC_LOGI " config init done. postpone handle mi services."
    uci -q set xiaoqiang.common.INITTED=YES
    uci commit xiaoqiang

    # led control
  if false; then
  whcal isre && {
    local str="$(xqwhc_re_getmetric_str)"
    if echo -n "$str" | grep -q -e "good" -e "mid" ; then
        led_link_good
    elif echo -n "$str" | grep -q "poor"; then
        led_link_poor
    else
        WHC_LOGI "   exception, postinit read a bad metric"
        cp $XQWHC_LINK_METRICS $XQWHC_LINK_METRICS_postinit_bad
    fi
  }
  fi

    # turn off web init redirect page
    /usr/sbin/sysapi webinitrdr set off &

    # set wps state for qca wifi
    /usr/sbin/set_wps_state 2 &

    WHC_LOGI "start mi service on $(xqwhc_get_stat) "
    __start_mi
    return 0
}


