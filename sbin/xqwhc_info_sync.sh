#!/bin/sh
# Copyright (C) 2016 Xiaomi
#

# for d01/r3600, called by trafficd handle whc_sync

USE_ENCODE=1


whcal isre || exit 0

. /lib/xqwhc/xqwhc_public.sh

xqwhc_lock="/var/run/xqwhc_wifi.lock"
cfgf="/var/run/xq_whc_sync"
cfgf_fake="/var/run/xq_whc_sync_fake"
son_changed=0   # wifi change, need wifi reset
sys_changed=0
miscan_changed=0
iot_switch_changed=0
B64_ENC=0

SUPPORT_GUEST_ON_RE=0   # for now, we only support guest network on CAP. so we don not handle guest opts

wifi_parse()
{
    #2g wifi-iface options
    local ssid_2_enc="`cat $cfgf | grep -w "ssid_2g" | awk -F ":=" '{print $2}'`"
    local pswd_2_enc="`cat $cfgf | grep -w "pswd_2g" | awk -F ":=" '{print $2}'`"
    local ssid_2="$ssid_2_enc"
    local pswd_2="$pswd_2_enc"
    if [ "$USE_ENCODE" -gt 0 ]; then
        ssid_2="$(base64_dec "$ssid_2_enc")"
        pswd_2="$(base64_dec "$pswd_2_enc")"
    fi
    local mgmt_2="`cat $cfgf | grep -w "mgmt_2g" | awk -F ":=" '{print $2}'`"
    local hidden_2="`cat $cfgf | grep -w "hidden_2g" | awk -F ":=" '{print $2}'`"
    local disabled_2="`cat $cfgf | grep -w "disabled_2g" | awk -F ":=" '{print $2}'`"
    local bsd_2="`cat $cfgf | grep -w "bsd_2g" | awk -F ":=" '{print $2}'`"
    local sae_2="`cat $cfgf | grep -w "sae_2g" | awk -F ":=" '{print $2}'`"
    local sae_pswd_2_enc="`cat $cfgf | grep -w "sae_passwd_2g" | awk -F ":=" '{print $2}'`"
    local sae_pswd_2="$sae_pswd_2_enc"
    if [ "$USE_ENCODE" -gt 0 ]; then
        sae_pswd_2="$(base64_dec "$sae_pswd_2")"
    fi
    local ieee80211w_2="`cat $cfgf | grep -w "ieee80211w_2g" | awk -F ":=" '{print $2}'`"

    [ -z "$ssid_2" ] && {
        WHC_LOGE " xq_whc_sync, wifi options 2g ssid invalid ignore!"
        cp "$cfgf" "$cfgf_fake"
        return 1
    }

    
    ssid_2_cur="`uci -q get wireless.@wifi-iface[1].ssid`"
    pswd_2_cur="`uci -q get wireless.@wifi-iface[1].key`"
    [ -z "pswd_2_cur" ] && pswd_2_cur=""
    mgmt_2_cur="`uci -q get wireless.@wifi-iface[1].encryption`"
    hidden_2_cur="`uci -q get wireless.@wifi-iface[1].hidden`"
    [ -z "$hidden_2_cur" ] && hidden_2_cur=0
    disabled_2_cur="`uci -q get wireless.@wifi-iface[1].disabled`"
    [ -z "$disabled_2_cur" ] && disabled_2_cur=0
    local bsd_2_cur="`uci -q get wireless.@wifi-iface[1].bsd`"
    [ -z "$bsd_2_cur" ] && bsd_2_cur=0
    local sae_2_cur="`uci -q get wireless.@wifi-iface[1].sae`"
    [ -z "$sae_2_cur" ] && sae_2_cur=""
    local sae_pswd_2_cur="`uci -q get wireless.@wifi-iface[1].sae_password`"
    [ -z "$sae_pswd_2_cur" ] && sae_pswd_2_cur=""
    local ieee80211w_2_cur="`uci -q get wireless.@wifi-iface[1].ieee80211w`"
    [ -z "$ieee80211w_2_cur" ] && ieee80211w_2_cur=""

    [ "$ssid_2_cur" != "$ssid_2" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, 2g ssid change $ssid_2_cur -> $ssid_2"
        uci set wireless.@wifi-iface[1].ssid="$ssid_2"
    }
    [ "$pswd_2_cur" != "$pswd_2" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, 2g pswd change $pswd_2_cur -> $pswd_2"
        if [ -n "$pswd_2" ]; then
            uci set wireless.@wifi-iface[1].key="$pswd_2"
        else
            uci -q delete wireless.@wifi-iface[1].key
        fi
    }
    [ "$mgmt_2_cur" != "$mgmt_2" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, 2g mgmt change $mgmt_2_cur -> $mgmt_2"
        uci set wireless.@wifi-iface[1].encryption="$mgmt_2"
    }
    [ "$hidden_2_cur" != "$hidden_2" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, 2g hidden change $hidden_2_cur -> $hidden_2"
        uci set wireless.@wifi-iface[1].hidden="$hidden_2"
    }
    [ "$disabled_2_cur" != "$disabled_2" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, 2g disabled change $disabled_2_cur -> $disabled_2"
        uci set wireless.@wifi-iface[1].disabled="$disabled_2"
    }
    [ "$bsd_2" != "$bsd_2_cur" ] && {
         son_changed=1
         WHC_LOGI " xq_whc_sync, 2g bsd change $bsd_2_cur -> $bsd_2"
         uci set wireless.@wifi-iface[1].bsd="$bsd_2"
         uci set lbd.config.PHYBasedPrioritization="$bsd_2"
         uci commit lbd
    }
    [ "$sae_2" != "$sae_2_cur" ] && {
         son_changed=1
         WHC_LOGI " xq_whc_sync, 2g sae change $sae_2_cur -> $sae_2"
         if [ -n "$sae_2" ];then
            uci set wireless.@wifi-iface[1].sae="$sae_2"
         else
            uci -q delete wireless.@wifi-iface[1].sae
         fi
    }
    [ "$sae_pswd_2" != "$sae_pswd_2_cur" ] && {
         son_changed=1
         WHC_LOGI " xq_whc_sync, 2g sae password change $sae_pswd_2_cur -> $sae_pswd_2"
         if [ -n "$sae_pswd_2" ];then
            uci set wireless.@wifi-iface[1].sae_password="$sae_pswd_2"
         else
            uci -q delete wireless.@wifi-iface[1].sae_password
         fi
    }
    [ "$ieee80211w_2" != "$ieee80211w_2_cur" ] && {
         son_changed=1
         WHC_LOGI " xq_whc_sync, 2g ieee80211w change $ieee80211w_2_cur -> $ieee80211w_2"
         if [ -n "$ieee80211w_2" ];then
            uci set wireless.@wifi-iface[1].ieee80211w="$ieee80211w_2"
         else
            uci -q delete wireless.@wifi-iface[1].ieee80211w
         fi
    }

    #5g wifi-iface options
    local ssid_5_enc="`cat $cfgf | grep -w "ssid_5g" | awk -F ":=" '{print $2}'`"
    local pswd_5_enc="`cat $cfgf | grep -w "pswd_5g" | awk -F ":=" '{print $2}'`"
    local ssid_5="$ssid_5_enc"
    local pswd_5="$pswd_5_enc"
    if [ "$USE_ENCODE" -gt 0 ]; then
        ssid_5="$(base64_dec "$ssid_5_enc")"
        pswd_5="$(base64_dec "$pswd_5_enc")"
    fi
    local mgmt_5="`cat $cfgf | grep -w "mgmt_5g" | awk -F ":=" '{print $2}'`"
    local hidden_5="`cat $cfgf | grep -w "hidden_5g" | awk -F ":=" '{print $2}'`"
    local disabled_5="`cat $cfgf | grep -w "disabled_5g" | awk -F ":=" '{print $2}'`"
    local bsd_5="`cat $cfgf | grep -w "bsd_5g" | awk -F ":=" '{print $2}'`"
    local sae_5="`cat $cfgf | grep -w "sae_5g" | awk -F ":=" '{print $2}'`"
    local sae_pswd_5_enc="`cat $cfgf | grep -w "sae_passwd_5g" | awk -F ":=" '{print $2}'`"
    local sae_pswd_5="$sae_pswd_5_enc"
    if [ "$USE_ENCODE" -gt 0 ]; then
        sae_pswd_5="$(base64_dec "$sae_pswd_5")"
    fi
    local ieee80211w_5="`cat $cfgf | grep -w "ieee80211w_5g" | awk -F ":=" '{print $2}'`"


    [ -z "$ssid_5" ] && {
        WHC_LOGE " xq_whc_sync, wifi options 5g ssid invalid ignore!"
        cp "$cfgf" "$cfgf_fake"
        return 1
    }

    
    ssid_5_cur="`uci -q get wireless.@wifi-iface[0].ssid`"
    pswd_5_cur="`uci -q get wireless.@wifi-iface[0].key`"
    [ -z "pswd_5_cur" ] && pswd_5_cur=""
    mgmt_5_cur="`uci -q get wireless.@wifi-iface[0].encryption`"
    hidden_5_cur="`uci -q get wireless.@wifi-iface[0].hidden`"
    [ -z "$hidden_5_cur" ] && hidden_5_cur=0
    disabled_5_cur="`uci -q get wireless.@wifi-iface[0].disabled`"
    [ -z "$disabled_5_cur" ] && disabled_5_cur=0
    local bsd_5_cur="`uci -q get wireless.@wifi-iface[0].bsd`"
    [ -z "$bsd_5_cur" ] && bsd_5_cur=0
    local sae_5_cur="`uci -q get wireless.@wifi-iface[0].sae`"
    [ -z "$sae_5_cur" ] && sae_5_cur=""
    local sae_pswd_5_cur="`uci -q get wireless.@wifi-iface[0].sae_password`"
    [ -z "$sae_pswd_5_cur" ] && sae_pswd_5_cur=""
    local ieee80211w_5_cur="`uci -q get wireless.@wifi-iface[0].ieee80211w`"
    [ -z "$ieee80211w_5_cur" ] && ieee80211w_5_cur=""


    [ "$ssid_5_cur" != "$ssid_5" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, 5g ssid change $ssid_5_cur -> $ssid_5"
        uci set wireless.@wifi-iface[0].ssid="$ssid_5"
    }
    [ "$pswd_5_cur" != "$pswd_5" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, 5g pswd change $pswd_5_cur -> $pswd_5"
        if [ -n "$pswd_5" ]; then
           uci set wireless.@wifi-iface[0].key="$pswd_5"
        else
           uci -q delete wireless.@wifi-iface[0].key
        fi
    }
    [ "$mgmt_5_cur" != "$mgmt_5" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, 5g mgmt change $mgmt_5_cur -> $mgmt_5"
        uci set wireless.@wifi-iface[0].encryption="$mgmt_5"
    }
    [ "$hidden_5_cur" != "$hidden_5" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, 5g hidden change $hidden_5_cur -> $hidden_5"
        uci set wireless.@wifi-iface[0].hidden="$hidden_5"
    }
    [ "$disabled_5_cur" != "$disabled_5" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, 5g disabled change $disabled_5_cur -> $disabled_5"
        uci set wireless.@wifi-iface[0].disabled="$disabled_5"
    }
    [ "$bsd_5" != "$bsd_5_cur" ] && {
         son_changed=1
         WHC_LOGI " xq_whc_sync, 5g bsd change $bsd_5_cur -> $bsd_5"
         uci set wireless.@wifi-iface[0].bsd="$bsd_5"
         uci set lbd.config.PHYBasedPrioritization="$bsd_5"
         uci commit lbd
    }
    [ "$sae_5" != "$sae_5_cur" ] && {
         son_changed=1
         WHC_LOGI " xq_whc_sync, 5g sae change $sae_5_cur -> $sae_5"
         if [ -n "$sae_5" ];then
            uci set wireless.@wifi-iface[0].sae="$sae_5"
         else
            uci -q delete wireless.@wifi-iface[0].sae
         fi
    }
    [ "$sae_pswd_5" != "$sae_pswd_5_cur" ] && {
         son_changed=1
         WHC_LOGI " xq_whc_sync, 5g sae password change $sae_pswd_5_cur -> $sae_pswd_5"
         if [ -n "$sae_pswd_5" ];then
            uci set wireless.@wifi-iface[0].sae_password="$sae_pswd_5"
         else
            uci -q delete wireless.@wifi-iface[0].sae_password
         fi
    }
    [ "$ieee80211w_5" != "$ieee80211w_5_cur" ] && {
         son_changed=1
         WHC_LOGI " xq_whc_sync, 5g ieee80211w change $ieee80211w_5_cur -> $ieee80211w_5"
         if [ -n "$ieee80211w_5" ];then
            uci set wireless.@wifi-iface[0].ieee80211w="$ieee80211w_5"
         else
            uci -q delete wireless.@wifi-iface[0].ieee80211w
         fi
    }
    
    #2g backhaul wifi-iface
    backhauls="`uci show misc.backhauls.backhaul`"
    flag="`echo $backhauls | grep 2g`"
    uplink_backhaul_2g="`uci show misc.backhauls.backhaul_2g_ap_iface|awk -F "'" '{print $2}'`"
    if [ "x$flag" != "x" -a "$uplink_backhaul_2g" == "wl1" ];then
        backhaul_2g="`uci show misc.backhauls.backhaul_2g_sta_iface|awk -F "'" '{print $2}'`"
        index="`uci show wireless|grep ifname|grep $backhaul_2g|awk -F "." '{print $2}'`"

        sta_ssid_2_cur="`uci -q get wireless.$index.ssid`"
        sta_pswd_2_cur="`uci -q get wireless.$index.key`"
        [ -z "$sta_pswd_2_cur" ] && sta_pswd_2_cur=0
        sta_mgmt_2_cur="`uci -q get wireless.$index.encryption`"
        sta_hidden_2_cur="`uci -q get wireless.$index.hidden`"
        [ -z "$sta_hidden_2_cur" ] && sta_hidden_2_cur=0
        sta_sae_2_cur="`uci -q get wireless.$index.sae`"
        [ -z "$sta_sae_2_cur" ] && sta_sae_2_cur=""
        sta_sae_pswd_2_cur="`uci -q get wireless.$index.sae_password`"
        [ -z "$sta_sae_pswd_2_cur" ] && sta_sae_pswd_2_cur=""
        sta_ieee80211w_2_cur="`uci -q get wireless.$index.ieee80211w`"
        [ -z "$sta_ieee80211w_2_cur" ] && sta_ieee80211w_2_cur=""

        [ "$sta_ssid_2_cur" != "$ssid_2" ] && {
            son_changed=1
            WHC_LOGI " xq_whc_sync, backhaul 2g ssid change $sta_ssid_2_cur -> $ssid_2"
            uci set wireless.$index.ssid="$ssid_2"
        }
        [ "$sta_pswd_2_cur" != "$pswd_2" ] && {
            son_changed=1
            WHC_LOGI " xq_whc_sync, backhaul 2g pswd change $sta_pswd_2_cur -> $pswd_2"
            if [ -n "$pswd_2" ]; then
                uci set wireless.$index.key="$pswd_2"
            else
                uci delete wireless.$index.key
            fi
        }
        [ "$sta_mgmt_2_cur" != "$mgmt_2" ] && {
            son_changed=1
            WHC_LOGI " xq_whc_sync, backhaul 2g mgmt change $sta_mgmt_2_cur -> $mgmt_2"
            uci set wireless.$index.encryption="$mgmt_2"
        }
        [ "$sta_hidden_2_cur" != "$hidden_2" ] && {
            son_changed=1
            WHC_LOGI " xq_whc_sync, backhaul 2g hidden change $sta_hidden_2_cur -> $hidden_2"
            uci set wireless.$index.hidden="$hidden_2"
        }
        [ "$sae_2" != "$sta_sae_2_cur" ] && {
            son_changed=1
            WHC_LOGI " xq_whc_sync, backhaul 2g sae change $sta_sae_2_cur -> $sae_2"
            if [ -n "$sae_2" ];then
                uci set wireless.$index.sae="$sae_2"
            else
                uci -q delete wireless.$index.sae
            fi
        }
        [ "$sae_pswd_2" != "$sta_sae_pswd_2_cur" ] && {
            son_changed=1
            WHC_LOGI " xq_whc_sync, backhaul 2g sae password change $sta_sae_pswd_2_cur -> $sae_pswd_2"
            if [ -n "$sae_pswd_2" ];then
                uci set wireless.$index.sae_password="$sae_pswd_2"
            else
                uci -q delete wireless.$index.sae_password
            fi
        }
        [ "$ieee80211w_2" != "$sta_ieee80211w_2_cur" ] && {
            son_changed=1
            WHC_LOGI " xq_whc_sync, backhaul 2g ieee80211w change $sta_ieee80211w_2_cur -> $ieee80211w_2"
            if [ -n "$ieee80211w_2" ];then
                uci set wireless.$index.ieee80211w="$ieee80211w_2"
            else
                uci -q delete wireless.$index.ieee80211w
            fi
        }
    fi

    #5g backhaul wifi-iface
    backhauls="`uci show misc.backhauls.backhaul`"
    flag="`echo $backhauls | grep  5g`"
    uplink_backhaul_5g="`uci show misc.backhauls.backhaul_5g_ap_iface|awk -F "'" '{print $2}'`"
    if [ "x$flag" != "x" -a "$uplink_backhaul_5g" == "wl0" ];then
        backhaul_5g="`uci show misc.backhauls.backhaul_5g_sta_iface|awk -F "'" '{print $2}'`"
        index="`uci show wireless|grep ifname|grep $backhaul_5g|awk -F "." '{print $2}'`"

        sta_ssid_5_cur="`uci -q get wireless.$index.ssid`"
        sta_pswd_5_cur="`uci -q get wireless.$index.key`"
        [ -z "$sta_pawd_5_cur" ] && sta_pawd_5_cur=0
        sta_mgmt_5_cur="`uci -q get wireless.$index.encryption`"
        sta_hidden_5_cur="`uci -q get wireless.$index.hidden`"
        [ -z "$sta_hidden_5_cur" ] && sta_hidden_5_cur=0
        sta_sae_5_cur="`uci -q get wireless.$index.sae`"
        [ -z "$sta_sae_5_cur" ] && sta_sae_5_cur=""
        sta_sae_pswd_5_cur="`uci -q get wireless.$index.sae_password`"
        [ -z "$sta_sae_pswd_5_cur" ] && sta_sae_pswd_5_cur=""
        sta_ieee80211w_5_cur="`uci -q get wireless.$index.ieee80211w`"
        [ -z "$sta_ieee80211w_5_cur" ] && sta_ieee80211w_5_cur=""

        [ "$sta_ssid_5_cur" != "$ssid_5" ] && {
            son_changed=1
            WHC_LOGI " xq_whc_sync, backhaul 5g ssid change $sta_ssid_5_cur -> $ssid_5"
            uci set wireless.$index.ssid="$ssid_5"
        }
        [ "$sta_pswd_5_cur" != "$pswd_5" ] && {
            son_changed=1
            WHC_LOGI " xq_whc_sync, backhaul 5g pswd change $sta_pswd_5_cur -> $pswd_5"
            if [ -n "$pswd_5" ]; then
                uci set wireless.$index.key="$pswd_5"
            else
                uci -q delete wireless.$index.key
            fi
        }
        [ "$sta_mgmt_5_cur" != "$mgmt_5" ] && {
            son_changed=1
            WHC_LOGI " xq_whc_sync, backhaul 5g mgmt change $sta_mgmt_5_cur -> $mgmt_5"
            uci set wireless.$index.encryption="$mgmt_5"
        }
        [ "$sta_hidden_5_cur" != "$hidden_5" ] && {
            son_changed=1
            WHC_LOGI " xq_whc_sync, backhaul 5g hidden change $sta_hidden_5_cur -> $hidden_5"
            uci set wireless.$index.hidden="$hidden_5"
        }
        [ "$sae_5" != "$sta_sae_5_cur" ] && {
            son_changed=1
            WHC_LOGI " xq_whc_sync, backhaul 5g sae change $sta_sae_5_cur -> $sae_5"
            if [ -n "$sae_5" ];then
                uci set wireless.$index.sae="$sae_5"
            else
                uci -q delete wireless.$index.sae
            fi
        }
        [ "$sae_pswd_5" != "$sta_sae_pswd_5_cur" ] && {
            son_changed=1
            WHC_LOGI " xq_whc_sync, backhaul 5g sae password change $sta_sae_pswd_5_cur -> $sae_pswd_5"
            if [ -n "$sae_pswd_5" ];then
                uci set wireless.$index.sae_password="$sae_pswd_5"
            else
                uci -q delete wireless.$index.sae_password
            fi
        }
        [ "$ieee80211w_5" != "$sta_ieee80211w_5_cur" ] && {
            son_changed=1
            WHC_LOGI " xq_whc_sync, backhaul 5g ieee80211w change $sta_ieee80211w_5_cur -> $ieee80211w_5"
            if [ -n "$ieee80211w_5" ];then
                uci set wireless.$index.ieee80211w="$ieee80211w_5"
            else
                uci -q delete wireless.$index.ieee80211w
            fi
        }

    fi

    # wifi-device options
    local txp_2="`cat $cfgf | grep -w "txpwr_2g" | awk -F ":=" '{print $2}'`"
    local ch_2="`cat $cfgf | grep -w "ch_2g" | awk -F ":=" '{print $2}'`"
    [ -z "$ch_2" -o "0" = "$ch_2" ] && ch_2="auto"
    local bw_2="`cat $cfgf | grep -w "bw_2g" | awk -F ":=" '{print $2}'`"
    local txbf_2="`cat $cfgf | grep -w "txbf_2g" | awk -F ":=" '{print $2}'`"
    local ax_2="`cat $cfgf | grep -w "ax_2g" | awk -F ":=" '{print $2}'`"
    local txp_2_cur="`uci -q get wireless.wifi1.txpwr`"
    [ -z "$txp_2_cur" ] && txp_2_cur="max"
    local ch_2_cur="`uci -q get wireless.wifi1.channel`"
    [ -z "$ch_2_cur" -o "0" = "$ch_2_cur" ] && ch_2_cur="auto"
    local bw_2_cur="`uci -q get wireless.wifi1.bw`"
    [ -z "$bw_2_cur" ] && bw_2_cur=0
    local txbf_2_cur="`uci -q get wireless.wifi1.txbf`"
    [ -z "$txbf_2_cur" ] && txbf_2_cur=3
    local ax_2_cur="`uci -q get wireless.wifi1.ax`"
    [ -z "$ax_2_cur" ] && ax_2_cur=1

    [ "$ch_2" != "$ch_2_cur" ] && {
        uci set wireless.wifi1.channel="$ch_2"
        # check real channel, if SAME then should save one wifi reset
        local ch_2_act="`iwlist wl1 channel | grep -Eo "\(Channel.*\)" | grep -Eo "[1-9]+"`"
        [ "$ch_2" != "$ch_2_act" ] && {
            son_changed=1
            WHC_LOGI " xq_whc_sync, wifi1 dev change channel $ch_2_act -> $ch_2 "
        }
    }

    [ "$txp_2" != "$txp_2_cur" -o "$bw_2" != "$bw_2_cur" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, wifi1 dev change $txp_2_cur:$bw_2_cur -> $txp_2:$bw_2 "
        uci set wireless.wifi1.txpwr="$txp_2"
        uci set wireless.wifi1.bw="$bw_2"
    }

    [ -n "$txbf_2" -a "$txbf_2" -ne "$txbf_2_cur" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, wifi1 dev change txbf [$txbf_2_cur] -> [$txbf_2]"
        uci set wireless.wifi1.txbf="$txbf_2"
    }
    [ -n "$ax_2" -a "$ax_2" -ne "$ax_2_cur" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, wifi1 dev change ax [$ax_2_cur] -> [$ax_2]"
        uci set wireless.wifi1.ax="$ax_2"
    }

    local txp_5="`cat $cfgf | grep -w "txpwr_5g" | awk -F ":=" '{print $2}'`"
    local ch_5="`cat $cfgf | grep -w "ch_5g" | awk -F ":=" '{print $2}'`"
    [ -z "$ch_5" -o "0" = "$ch_5" ] && ch_5="auto"
    local bw_5="`cat $cfgf | grep -w "bw_5g" | awk -F ":=" '{print $2}'`"
    local txbf_5="`cat $cfgf | grep -w "txbf_5g" | awk -F ":=" '{print $2}'`"
    local ax_5="`cat $cfgf | grep -w "ax_5g" | awk -F ":=" '{print $2}'`"
    local txp_5_cur="`uci -q get wireless.wifi0.txpwr`"
    [ -z "$txp_5_cur" ] && txp_5_cur="max"
    local ch_5_cur="`uci -q get wireless.wifi0.channel`"
    [ -z "$ch_5_cur" -o "0" = "$ch_5_cur" ] && ch_5_cur="auto"
    local bw_5_cur="`uci -q get wireless.wifi0.bw`"
    [ -z "$bw_5_cur" ] && bw_5_cur=0
    local txbf_5_cur="`uci -q get wireless.wifi0.txbf`"
    [ -z "$txbf_5_cur" ] && txbf_5_cur=3
    local ax_5_cur="`uci -q get wireless.wifi0.ax`"
    [ -z "$ax_5_cur" ] && ax_5_cur=1
    local support160="`cat $cfgf | grep -w "support160" | awk -F ":=" '{print $2}'`"

    [ "$ch_5" != "$ch_5_cur" ] && {
        uci set wireless.wifi0.channel="$ch_5"
        # check real channel, if SAME then should save one wifi reset
        local ch_5_act="`iwlist wl0 channel | grep -Eo "\(Channel.*\)" | grep -Eo "[1-9]+"`"
        [ "$ch_5" != "$ch_5_act" ] && {
            son_changed=1
            WHC_LOGI " xq_whc_sync, wifi0 dev change channel $ch_5_act -> $ch_5 "
        }
    }
    [ "$txp_5" != "$txp_5_cur"] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, wifi0 dev change $txp_5_cur -> $txp_5"
        uci set wireless.wifi0.txpwr="$txp_5"
    }

    [ "$bw_5" != "$bw_5_cur" ] && {
        if [ "$bw_5" != "0" ]; then
            son_changed=1
            WHC_LOGI " xq_whc_sync, wifi0 dev change $bw_5_cur -> $bw_5"
            uci set wireless.wifi0.bw="$bw_5"
        else
            if [ "$support160" = "1" ]; then
                son_changed=1
                WHC_LOGI " xq_whc_sync, wifi0 dev change $bw_5_cur -> $bw_5"
                uci set wireless.wifi0.bw="$bw_5"
            else
                if [ "$bw_5_cur" != "80" ]; then
                    son_changed=1
                    WHC_LOGI " xq_whc_sync, cap do not support 160m, cap 0 means 80, $bw_5_cur -> 80"
                    uci set wireless.wifi0.bw='80'
                fi
            fi
        fi
    }

    [ -n "$txbf_5" -a "$txbf_5" -ne "$txbf_5_cur" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, wifi0 dev change txbf [$txbf_5_cur] -> [$txbf_5]"
        uci set wireless.wifi0.txbf="$txbf_5"
    }

    [ -n "$ax_5" -a "$ax_5" -ne "$ax_5_cur" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, wifi0 dev change ax [$ax_5_cur] -> [$ax_5]"
        uci set wireless.wifi0.ax="$ax_5"
    }

    #iot switch
    local iot_switch_cur="`uci -q get wireless.miot_2G.userswitch`"
    [ -z "$iot_switch_cur" ] && iot_switch_cur=1
    local iot_switch="`cat $cfgf | grep -w "iot_switch" | awk -F ":=" '{print $2}'`"
    [ -n "$iot_switch" -a "$iot_switch" -ne "$iot_switch_cur" ] && {
        iot_switch_changed=1
        WHC_LOGI " xq_whc_sync, iot user switch changed [$iot_switch_cur] -> [$iot_switch]"
        uci set wireless.miot_2G.userswitch="$iot_switch"
    }

    uci commit wireless && sync
    return 0;
}

guest_parse()
{
    local gst_sect="guest"

    local disab="`cat $cfgf | grep -w "gst_disab" | awk -F ":=" '{print $2}'`"
    [ -z "$disab" ] && disab=0
    local ssid_enc="`cat $cfgf | grep -w "gst_ssid" | awk -F ":=" '{print $2}'`"
    local pswd_enc="`cat $cfgf | grep -w "gst_pswd" | awk -F ":=" '{print $2}'`"
    local ssid="$ssid_enc"
    local pswd="$pswd_enc"
    if [ "$USE_ENCODE" -gt 0 ]; then
        ssid="$(base64_dec "$ssid_enc")"
        pswd="$(base64_dec "$pswd_enc")"
    fi
    local mgmt="`cat $cfgf | grep -w "gst_mgmt" | awk -F ":=" '{print $2}'`"

    [ -z "$ssid" ] && {
        WHC_LOGE " xq_whc_sync, guest options invalid ignore!"
        cp "$cfgf" "$cfgf_fake"
        return 1
    }

    # if guest section no exist, create first
    local disab_cur=0
    local ssid_cur=""
    local pswd_cur=""
    local mgmt_cur=""

    if uci -q get wireless.$gst_sect >/dev/null 2>&1; then
        disab_cur="`uci -q get wireless.$gst_sect.disabled`"
        [ -z "$disab_cur" ] && disab_cur=0;
        ssid_cur="`uci -q get wireless.$gst_sect.ssid`"
        pswd_cur="`uci -q get wireless.$gst_sect.key`"
        mgmt_cur="`uci -q get wireless.$gst_sect.encryption`"
    else
        WHC_LOGI " xq_whc_sync, guest section newly add, TODO son options"
        disab_cur=1;
        uci set wireless.$gst_sect=wifi-iface
        uci set wireless.$gst_sect.device='wifi0'
        uci set wireless.$gst_sect.mode='ap'
        uci set wireless.$gst_sect.ifname='wl3'
        ##### TODO, guest iface options
    fi

    [ "$ssid_cur" != "$ssid" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, guest ssid change $ssid_cur -> $ssid"
        #uci set wireless.$gst_sect.ssid="$ssid"
    }
    [ "$pswd_cur" != "$pswd" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, guest pswd change $pswd_cur -> $pswd"
        uci set wireless.$gst_sect.key="$pswd"
    }
    [ "$mgmt_cur" != "$mgmt" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, guest mgmt change $mgmt_cur -> $mgmt"
        uci set wireless.$gst_sect.encryption="$mgmt"
    }
    
    if [ "$disab_cur" != "$disab" ]; then
        son_changed=1
        WHC_LOGI " xq_whc_sync, guest disab change $disab_cur -> $disab"
        uci set wireless.$gst_sect.disabled="$disab"
    else
        [ "$disab" = 1 -a "$son_changed" -gt 0 ] && {
            WHC_LOGI " xq_whc_sync, guest disab, with option change, ignore reset"
            son_changed=0
        }
    fi

    uci commit wireless && sync

    return 0
}

system_parse()
{
    local timezone="`cat $cfgf | grep -w "timezone" | awk -F ":=" '{print $2}'`"
    local timezone_cur="`uci -q get system.@system[0].timezone`"
    [ "$timezone_cur" != "$timezone" ] && {
        sys_changed=1
        WHC_LOGI " xq_whc_sync, system timezone change $timezone_cur -> $timezone"
        uci set system.@system[0].timezone="$timezone"
        uci commit system
    }

    local ota_auto="`cat $cfgf | grep -w "ota_auto" | awk -F ":=" '{print $2}'`"
    [ -z "$ota_auto" ] && ota_auto=0
    local ota_auto_cur="`uci -q get otapred.settings.auto`"
    [ -z "$ota_auto_cur" ] && ota_auto_cur=0
    local ota_time="`cat $cfgf | grep -w "ota_time" | awk -F ":=" '{print $2}'`"
    local ota_time_cur="`uci -q get otapred.settings.time`"
    [ -z "$ota_time_cur" ] && ota_time_cur=4
    [ "$ota_auto" != "$ota_auto_cur" -o "$ota_time" != "$ota_time_cur" ] && {
        sys_changed=1
        WHC_LOGI " xq_whc_sync, system ota change $ota_auto_cur,$ota_time_cur -> $ota_auto,$ota_time"
        uci set otapred.settings.auto="$ota_auto"
        uci set otapred.settings.time="$ota_time"
        uci commit otapred
    }

    local led_blue="`cat $cfgf | grep -w "led_blue" | awk -F ":=" '{print $2}'`"
    [ -z "$led_blue" ] && led_blue=1
    local led_blue_cur="`uci -q get xiaoqiang.common.BLUE_LED`"
    [ -z "$led_blue_cur" ] && led_blue_cur=1
    [ "$led_blue" != "$led_blue_cur" ] && {
        sys_changed=0
        WHC_LOGI " xq_whc_sync, system led change $led_blue_cur -> $led_blue"
        uci set xiaoqiang.common.BLUE_LED="$led_blue"
        uci commit xiaoqiang
        local miscan_enable_cur="`uci -q get miscan.config.enabled`"
        [ "$led_blue" -eq 0 ] && {
            gpio 3 1;gpio 5 1;gpio 6 1
        } || {
            # led_blue on, let metric decide led beheave
            #/etc/init.d/xqwhc restart
           if [ "$miscan_enable_cur" != "0" ]; then
               gpio 3 0;gpio 5 0;gpio 6 0;[ -f /usr/sbin/wan_check.sh ] && /usr/sbin/wan_check.sh reset
           else
               gpio 3 0;gpio 5 0;[ -f /usr/sbin/wan_check.sh ] && /usr/sbin/wan_check.sh reset
           fi
        }
    }

    return 0
}

miscan_parse()
{
    local miscan_enable="`cat $cfgf | grep -w "miscan_enable" | awk -F ":=" '{print $2}'`"
    local miscan_enable_cur="`uci -q get miscan.config.enabled`"
    [ "$miscan_enable_cur" != "$miscan_enable" ] && {
        miscan_changed=1
        WHC_LOGI " xq_whc_sync, miscan status change $miscan_enable_cur -> $miscan_enable"
        uci set miscan.config.enabled="$miscan_enable"
        uci commit miscan
    }

    return 0
}

# must call guest_parse first
[ "$SUPPORT_GUEST_ON_RE" -gt 0 ] && {
    guest_parse || exit $?
}
wifi_parse || return $?
system_parse
miscan_parse

if [ "$miscan_changed" -gt 0 ]; then
    WHC_LOGI " xq_whc_sync, miscan_changed, restart miscan!"
    (/etc/init.d/scan restart) &
fi

if [ "$iot_switch_changed" -gt 0 ]; then
    WHC_LOGI " xq_whc_sync, iot user switch changed!"
    userswitch="`uci -q get wireless.miot_2G.userswitch`"
    miot_2g_ifname="`uci -q get misc.wireless.iface_miot_2g_ifname`"
    bindstatus="`uci -q get wireless.miot_2G.bindstatus`"
    if [ "$bindstatus" = "1" ]; then
        if [ "$userswitch" != "0" ]; then
            hostapd_cli -i "$miot_2g_ifname" -p /var/run/hostapd-wifi1 enable
        else
            hostapd_cli -i "$miot_2g_ifname" -p /var/run/hostapd-wifi1 disable
        fi
    fi
fi

if [ "$sys_changed" -gt 0 ]; then
    WHC_LOGI " xq_whc_sync, sys_changed, restart ntp!"
    # wait son update and reconnect
    if [ "$son_changed" -gt 0 ]; then
        (sleep 60; ntpsetclock now) &
    else
        (ntpsetclock now) &
    fi
fi


if [ "$son_changed" -gt 0 ]; then
    WHC_LOGI " xq_whc_sync, son_changed, need reset son!"
    ( lock "$xqwhc_lock";
    /etc/init.d/repacd restart_in_re_mode;
    lock -u "$xqwhc_lock" ) &

else
    WHC_LOGD " xq_whc_sync, son NO change!"
fi

