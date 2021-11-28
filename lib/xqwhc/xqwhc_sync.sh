#!/bin/sh

# xqwhc_sync: sync xqwhc

. /lib/xqwhc/xqwhc_public.sh


ERR_SYNC=60
ERR_SYNC_TIMEOUT=61
ERR_SYNC_ERR_WITHMSG=62
ERR_SYNC_WITHOUT_RE=63

wifi_xqwhc_lock="/var/run/xqwhc_wifi.lock"

# xqwhc sync method
SYNC_USE_QCA=0  # disabled after trafficd ready
RETRY_MAX=3
RET_OK="success"
FCFG_SYNC="/var/run/trafficd_whc_sync_cap"

USE_ENCODE=1
SUPPORT_GUEST_ON_RE=0 # for now, we only support guest network on CAP. so we don not handle guest opts

__get_wifi()
{
    ssid_2g="`uci -q get wireless.@wifi-iface[1].ssid`"
    pswd_2g="`uci -q get wireless.@wifi-iface[1].key`"
    [ -z "$pswd_2g" ] && pswd_2g=""
    mgmt_2g="`uci -q get wireless.@wifi-iface[1].encryption`"
    hidden_2g="`uci -q get wireless.@wifi-iface[1].hidden`"
    [ -z "$hidden_2g" ] && hidden_2g=0
    disabled_2g="`uci -q get wireless.@wifi-iface[1].disabled`"
    [ -z "$disabled_2g" ] && disabled_2g=0

    ssid_5g="`uci -q get wireless.@wifi-iface[0].ssid`"
    pswd_5g="`uci -q get wireless.@wifi-iface[0].key`"
    [ -z "$pswd_5g" ] && pswd_5g=""
    mgmt_5g="`uci -q get wireless.@wifi-iface[0].encryption`"
    hidden_5g="`uci -q get wireless.@wifi-iface[0].hidden`"
    [ -z "$hidden_5g" ] && hidden_5g=0
    disabled_5g="`uci -q get wireless.@wifi-iface[0].disabled`"
    [ -z "$disabled_5g" ] && disabled_5g=0

    txpwr_2g="`uci -q get wireless.wifi1.txpwr`"
    [ -z "$txpwr_2g" ] && txpwr_2g=max

    ch_2g="`uci -q get wireless.wifi1.channel`"
    [ -z "$ch_2g" ] && ch_2g="auto"

    bw_2g="`uci -q get wireless.wifi1.bw`"
    [ -z "$bw_2g" ] && bw_2g=0

    txbf_2g="`uci -q get wireless.wifi1.txbf`"
    [ -z "$txbf_2g" ] && txbf_2g=3

    ax_2g="`uci -q get wireless.wifi1.ax`"
    [ -z "$ax_2g" ] && ax_2g=1

    txpwr_5g="`uci -q get wireless.wifi0.txpwr`"
    [ -z "$txpwr_5g" ] && txpwr_5g=max

    ch_5g="`uci -q get wireless.wifi0.channel`"
    [ -z "$ch_5g" ] && ch_5g="auto"

    bw_5g="`uci -q get wireless.wifi0.bw`"
    [ -z "$bw_5g" ] && bw_5g=0

    txbf_5g="`uci -q get wireless.wifi0.txbf`"
    [ -z "$txbf_5g" ] && txbf_5g=3

    ax_5g="`uci -q get wireless.wifi0.ax`"
    [ -z "$ax_5g" ] && ax_5g=1

    bsd_2g="`uci -q get wireless.@wifi-iface[1].bsd`"
    [ -z "$bsd_2g" ] && bsd_2g=0

    bsd_5g="`uci -q get wireless.@wifi-iface[0].bsd`"
    [ -z "$bsd_5g" ] && bsd_5g=0

    sae_2g="`uci -q get wireless.@wifi-iface[1].sae`"
    [ -z "$sae_2g" ] && sae_2g=""

    sae_5g="`uci -q get wireless.@wifi-iface[0].sae`"
    [ -z "$sae_5g" ] && sae_5g=""

    sae_pwd_2g="`uci -q get wireless.@wifi-iface[1].sae_password`"
    [ -z "$sae_pwd_2g" ] && sae_pwd_2g=""

    sae_pwd_5g="`uci -q get wireless.@wifi-iface[0].sae_password`"
    [ -z "$sae_pwd_5g" ] && sae_pwd_5g=""

    ieee80211w_2g="`uci -q get wireless.@wifi-iface[1].ieee80211w`"
    [ -z "$ieee802211w_2g" ] && ieee802211w_2g=""

    ieee80211w_5g="`uci -q get wireless.@wifi-iface[0].ieee80211w`"
    [ -z "$ieee802211w_5g" ] && ieee802211w_5g=""

    support160="`uci -q get misc.wireless.support_160m`"
    [ -z "$support160" ] && support160=0

    iot_switch="`uci -q get wireless.miot_2G.userswitch`"
    [ -z "$iot_switch" ] && iot_switch=""

    [ "$USE_ENCODE" -gt 0 ] || {
    # support special string escape
        ssid_2g="$(str_escape "$ssid_2g")"
        pswd_2g="$(str_escape "$pswd_2g")"
        ssid_5g="$(str_escape "$ssid_5g")"
        pswd_5g="$(str_escape "$pswd_5g")"
        sae_pwd_2g="$(str_escape "$sae_pwd_2g")"
        sae_pwd_5g="$(str_escape "$sae_pwd_5g")"
    }
}

__get_bh_wifi()
{
    local iface_5g_name=`uci -q get misc.backhauls.backhaul_5g_ap_iface`
    local iface_5g_no=`uci show wireless|grep $iface_5g_name|awk -F "." '{print $2}'`
    if [ -n "$iface_5g_no" ]; then
        ssid_bh="`uci -q get wireless.$iface_5g_no.ssid`"
        pswd_bh="`uci -q get wireless.$iface_5g_no.key`"
        mgmt_bh="`uci -q get wireless.$iface_5g_no.encryption`"
        maclist_5g="`uci -q get wireless.$iface_5g_no.maclist`"
        maclist_5g_format="`echo -n $maclist_5g | sed "s/ /;/g"`"
        filter_5g="`uci -q get wireless.$iface_5g_no.macfilter`"
    else
        random_ssid_str="`dd if=/dev/urandom bs=1 count=6 2> /dev/null | openssl base64`"
        ssid_bh="MiMesh_$random_ssid_str"
        pswd_bh="`dd if=/dev/urandom bs=1 count=12 2> /dev/null | openssl base64`"
        mgmt_bh="psk2"
        maclist_5g=""
        maclist_5g_format=""
        filter_5g=""
    fi

    echo "$ssid_bh" > /tmp/ssid_backhaul_init
    echo "$pswd_bh" > /tmp/pswd_backhaul_init
}

__get_guest()
{
    local gst_sect="guest"

    [ "`uci -q get wireless.$gst_sect`" = "wifi-iface" ] && {
        gst_disab="uci -q get wireless.$gst_sect.disabled"
        [ -z "$gst_disab" ] && gst_disab=0
        gst_ssid="`uci -q get wireless.$gst_sect.ssid`"
        gst_pswd="`uci -q get wireless.$gst_disab.key`"
        gst_mgmt="`uci -q get wireless.$gst_disab.encryption`"
    }|| {
        gst_disab=1
        gst_ssid=""
        gst_pswd=""
        gst_mgmt=""
    }

    [ "$USE_ENCODE" -gt 0 ] || {
    # support special string escape
        gst_ssid="$(str_escape "$gst_ssid")"
        gst_pswd="$(str_escape "$gst_pswd")"
    }
}

__get_system()
{
    timezone="`uci -q get system.@system[0].timezone`"
    ota_auto="`uci -q get otapred.settings.auto`"
    [ -z "$ota_auto" ] && {
        ota_auto=0
        uci set otapred.settings.auto=0
        uci commit otapred
    }

    ota_time="`uci -q get otapred.settings.time`"
    [ -z "$ota_time" ] && {
        ota_time=4
        uci set otapred.settings.time="$ota_time"
        uci commit otapred
    }

    led_blue="`uci -q get xiaoqiang.common.BLUE_LED`"
    [ -z "$led_blue" ] && led_blue=1

}

__get_miscan()
{
    miscan_enable="`uci -q get miscan.config.enabled`"
    [ -z "$miscan_enable" ] && miscan_enable=1
}

__info_compose()
{
    # collect whc_sync msg & push to REs
#tbus call 192.168.31.115 whc_sync "{\"ssid_2g\":\"!@D01-son\",\"ssid_5g\":\"!@D01-son\",\"pswd_2g\":\"123456789\",\"pswd_5g\":\"123456789\",\"mgmt_2g\":\"mixed-psk\",\"mgmt_5g\":\"mixed-psk\",\"txpwr_2g\":\"max\",\"txpwr_5g\":\"max\",\"hidden_2g\":\"0\",\"hidden_5g\":\"0\,\"ch_2g\":\"1\",\"ch_5g\":\"161\",\"bw_2g\":\"0\",\"bw_5g\":\"0\",\"bsd_2g\":\"1\",\"bsd_5g\":\"1\",\"txbf_2g\":\"0\",\"txbf_5g\":\"0\",\sae_2g\":\"1\",\"sae_5g\":\"1\",\"sae_passwd_2g\":\"123456789\",\"sae_passwd_5g\":\"123456789\",\"ieee80211w_2g\":\"1\",\"ieee80211w_5g\":\"1\",\"gst_disab\":\"1\",\"gst_ssid\":\"\",\"gst_pswd\":\"\",\"gst_mgmt\":\"\",\"timezone\":\"CST-8\",\"ota_auto\":\"0\",\"ota_time\":\"4\",\"led_blue\":\"1\"}"

    __get_wifi
[ "$SUPPORT_GUEST_ON_RE" -gt 0 ] && {
    __get_guest
}
    __get_system
    __get_miscan

if [ "$SUPPORT_GUEST_ON_RE" -gt 0 ]; then
    msg_decode="{\
\"ssid_2g\":\"$ssid_2g\",\"ssid_5g\":\"$ssid_5g\",\"pswd_2g\":\"$pswd_2g\",\"pswd_5g\":\"$pswd_5g\",\
\"mgmt_2g\":\"$mgmt_2g\",\"mgmt_5g\":\"$mgmt_5g\",\"hidden_2g\":\"$hidden_2g\",\"hidden_5g\":\"$hidden_5g\",\
\"disabled_2g\":\"$disabled_2g\",\"disabled_5g\":\"$disabled_5g\",\"ax_2g\":\"$ax_2g\",\"ax_5g\":\"$ax_5g\",\
\"txpwr_2g\":\"$txpwr_2g\",\"txpwr_5g\":\"$txpwr_5g\",\"ch_2g\":\"$ch_2g\",\"ch_5g\":\"$ch_5g\",\
\"bw_2g\":\"$bw_2g\",\"bw_5g\":\"$bw_5g\",\"bsd_2g\":\"$bsd_2g\",\"bsd_5g\":\"$bsd_5g\",\"txbf_2g\":\"$txbf_2g\",\"txbf_5g\":\"$txbf_5g\",\
\"sae_2g\":\"$sae_2g\",\"sae_5g\":\"$sae_5g\",\"sae_passwd_2g\":\"$sae_pwd_2g\",\"sae_passwd_5g\":\"$sae_pwd_5g\",\
\"ieee80211w_2g\":\"$ieee80211w_2g\",\"ieee80211w_5g\":\"$ieee80211w_5g\",\
\"gst_disab\":\"$gst_disab\",\"gst_ssid\":\"$gst_ssid\",\"gst_pswd\":\"$gst_pswd\",\"gst_mgmt\":\"$gst_mgmt\",\
\"timezone\":\"$timezone\",\"ota_auto\":\"$ota_auto\",\"ota_time\":\"$ota_time\",\"led_blue\":\"$led_blue\",\"miscan_enable\":\"$miscan_enable\",\"support160\":\"$support160\",\
\"iot_switch\":\"$iot_switch\"\
}"

    msg="$msg_decode"
    if [ "$USE_ENCODE" -gt 0 ]; then
    msg="{\
\"ssid_2g\":\"$(base64_enc "$ssid_2g")\",\"ssid_5g\":\"$(base64_enc "$ssid_5g")\",\"pswd_2g\":\"$(base64_enc "$pswd_2g")\",\"pswd_5g\":\"$(base64_enc "$pswd_5g")\",\
\"mgmt_2g\":\"$mgmt_2g\",\"mgmt_5g\":\"$mgmt_5g\",\"hidden_2g\":\"$hidden_2g\",\"hidden_5g\":\"$hidden_5g\",\
\"disabled_2g\":\"$disabled_2g\",\"disabled_5g\":\"$disabled_5g\",\"ax_2g\":\"$ax_2g\",\"ax_5g\":\"$ax_5g\",\
\"txpwr_2g\":\"$txpwr_2g\",\"txpwr_5g\":\"$txpwr_5g\",\"ch_2g\":\"$ch_2g\",\"ch_5g\":\"$ch_5g\",\
\"bw_2g\":\"$bw_2g\",\"bw_5g\":\"$bw_5g\",\"bsd_2g\":\"$bsd_2g\",\"bsd_5g\":\"$bsd_5g\",\"txbf_2g\":\"$txbf_2g\",\"txbf_5g\":\"$txbf_5g\",\
\"sae_2g\":\"$sae_2g\",\"sae_5g\":\"$sae_5g\",\"sae_passwd_2g\":\"$(base64_enc "$sae_pwd_2g")\",\"sae_passwd_5g\":\"$(base64_enc "$sae_pwd_5g")\",\
\"ieee80211w_2g\":\"$ieee80211w_2g\",\"ieee80211w_5g\":\"$ieee80211w_5g\",\
\"gst_disab\":\"$gst_disab\",\"gst_ssid\":\"$gst_ssid\",\"gst_pswd\":\"$gst_pswd\",\"gst_mgmt\":\"$gst_mgmt\",\
\"timezone\":\"$timezone\",\"ota_auto\":\"$ota_auto\",\"ota_time\":\"$ota_time\",\"led_blue\":\"$led_blue\",\"miscan_enable\":\"$miscan_enable\",\"support160\":\"$support160\",\
\"iot_switch\":\"$iot_switch\"\
}"
    fi
else
    msg_decode="{\
\"ssid_2g\":\"$ssid_2g\",\"ssid_5g\":\"$ssid_5g\",\"pswd_2g\":\"$pswd_2g\",\"pswd_5g\":\"$pswd_5g\",\
\"mgmt_2g\":\"$mgmt_2g\",\"mgmt_5g\":\"$mgmt_5g\",\"hidden_2g\":\"$hidden_2g\",\"hidden_5g\":\"$hidden_5g\",\
\"disabled_2g\":\"$disabled_2g\",\"disabled_5g\":\"$disabled_5g\",\"ax_2g\":\"$ax_2g\",\"ax_5g\":\"$ax_5g\",\
\"txpwr_2g\":\"$txpwr_2g\",\"txpwr_5g\":\"$txpwr_5g\",\"ch_2g\":\"$ch_2g\",\"ch_5g\":\"$ch_5g\",\
\"bw_2g\":\"$bw_2g\",\"bw_5g\":\"$bw_5g\",\"bsd_2g\":\"$bsd_2g\",\"bsd_5g\":\"$bsd_5g\",\"txbf_2g\":\"$txbf_2g\",\"txbf_5g\":\"$txbf_5g\",\
\"sae_2g\":\"$sae_2g\",\"sae_5g\":\"$sae_5g\",\"sae_passwd_2g\":\"$sae_pwd_2g\",\"sae_passwd_5g\":\"$sae_pwd_5g\",\
\"ieee80211w_2g\":\"$ieee80211w_2g\",\"ieee80211w_5g\":\"$ieee80211w_5g\",\
\"timezone\":\"$timezone\",\"ota_auto\":\"$ota_auto\",\"ota_time\":\"$ota_time\",\"led_blue\":\"$led_blue\",\"miscan_enable\":\"$miscan_enable\",\"support160\":\"$support160\",\
\"iot_switch\":\"$iot_switch\"\
}"

    msg="$msg_decode"
    if [ "$USE_ENCODE" -gt 0 ]; then
    msg="{\
\"ssid_2g\":\"$(base64_enc "$ssid_2g")\",\"ssid_5g\":\"$(base64_enc "$ssid_5g")\",\"pswd_2g\":\"$(base64_enc "$pswd_2g")\",\"pswd_5g\":\"$(base64_enc "$pswd_5g")\",\
\"mgmt_2g\":\"$mgmt_2g\",\"mgmt_5g\":\"$mgmt_5g\",\"hidden_2g\":\"$hidden_2g\",\"hidden_5g\":\"$hidden_5g\",\
\"disabled_2g\":\"$disabled_2g\",\"disabled_5g\":\"$disabled_5g\",\"ax_2g\":\"$ax_2g\",\"ax_5g\":\"$ax_5g\",\
\"txpwr_2g\":\"$txpwr_2g\",\"txpwr_5g\":\"$txpwr_5g\",\"ch_2g\":\"$ch_2g\",\"ch_5g\":\"$ch_5g\",\
\"bw_2g\":\"$bw_2g\",\"bw_5g\":\"$bw_5g\",\"bsd_2g\":\"$bsd_2g\",\"bsd_5g\":\"$bsd_5g\",\"txbf_2g\":\"$txbf_2g\",\"txbf_5g\":\"$txbf_5g\",\
\"sae_2g\":\"$sae_2g\",\"sae_5g\":\"$sae_5g\",\"sae_passwd_2g\":\"$(base64_enc "$sae_pwd_2g")\",\"sae_passwd_5g\":\"$(base64_enc "$sae_pwd_5g")\",\
\"ieee80211w_2g\":\"$ieee80211w_2g\",\"ieee80211w_5g\":\"$ieee80211w_5g\",\
\"timezone\":\"$timezone\",\"ota_auto\":\"$ota_auto\",\"ota_time\":\"$ota_time\",\"led_blue\":\"$led_blue\",\"miscan_enable\":\"$miscan_enable\",\"support160\":\"$support160\",\
\"iot_switch\":\"$iot_switch\"\
}"
    fi

fi
}

__init_info_compose()
{
    __get_wifi
    __get_system

    init_msg="{\
\"hidden_2g\":\"$hidden_2g\",\"hidden_5g\":\"$hidden_5g\",\
\"disabled_2g\":\"$disabled_2g\",\"disabled_5g\":\"$disabled_5g\",\"ax_2g\":\"$ax_2g\",\"ax_5g\":\"$ax_5g\",\
\"txpwr_2g\":\"$txpwr_2g\",\"txpwr_5g\":\"$txpwr_5g\",\"ch_2g\":\"$ch_2g\",\"ch_5g\":\"$ch_5g\",\
\"bw_2g\":\"$bw_2g\",\"bw_5g\":\"$bw_5g\",\"txbf_2g\":\"$txbf_2g\",\"txbf_5g\":\"$txbf_5g\",\
\"support160\":\"$support160\"\
}"
}
__syncbuf_compare()
{
    local msg_pre=`cat $FCFG_SYNC | grep -E "ssid.*pswd.*mgmt.*" | awk 'END{print $0}'`
    local msg_now="$1"
    [ "$msg_pre" = "$msg_now" ]
}

## sync_jsonbuf
# output jsonbuf as input for tbus call * whc_sync "$jsonbuf"
xqwhc_sync_jsonbuf()
{
    __info_compose
    echo "$msg"

    __syncbuf_compare "$msg" || WHC_LOGI " whc_sync reply msg=<\"$msg\">"
    echo "`date +%Y%m%d-%H%M%S` whc_sync reply msg compose on CAP:" > "$FCFG_SYNC"
    echo "$msg_decode" >> "$FCFG_SYNC"
    echo "$msg" >> "$FCFG_SYNC"
}

xqwhc_init_jsonbuf()
{
    __init_info_compose
    echo "$init_msg"
}

__if_whc_re()
{
    tbus -v list "$1" 2>/dev/null | grep -qE "whc_sync[:\",]+" || {
        WHC_LOGI " whc_sync tbus clt $1 is NOT RE! "
        return 1
    }
    return 0
}

__if_whc_re_alive()
{
    buff="`timeout -t 5 tbus call "$1" whc_quire 2>/dev/null`"
    res="`json_get_value "$buff" "return"`"
    
    if [ "$res" = "$RET_OK" ]; then
        WHC_LOGI " xqwhc_sync $1 check alive!"
        return 0
    else
        WHC_LOGI " xqwhc_sync $1 check NOT alive! "
        return 11
    fi

}


## notify REs with precompose cmd, if re exist&active
# 1. get and validate WHC_RE active in tbus list, exclude repeater
# 2. run tbus cmd
notify_re()
{
    . /usr/share/libubox/jshn.sh
    json_init
    json_add_string "method" "whc_sync"
    json_add_string "payload" $jmsg
    json_str=`json_dump`
                ### check if re node still exist in tbus list?
    echo $json_str
                # if re node quire alive
    WHC_LOGI " ubus call xq_info_sync_mqtt send_msg "$json_str" "
    ubus call xq_info_sync_mqtt send_msg "$json_str"
    return 1
}

xqwhc_sync()
{
    local fail=0
    [ "$SYNC_USE_QCA" -gt 0 ] && {
        . /lib/xqwhc/xqwhc_hyt.sh
        local cnt=$(xqwhc_get_recnt)
        [ "$cnt" -eq 0 ] && return $ERR_SYNC_WITHOUT_RE

        WHC_LOGI " whc_sync SYNC_USE_QCA=1, wifi reset in 20 secs!"
        [ -f /etc/init.d/wsplcd ] && /etc/init.d/wsplcd restart_after_config_change &
        return 0
    }

    local msg=""
    __info_compose

    WHC_LOGI " whc_sync note msg=<\"$msg\">"
    echo "`date +%Y%m%d-%H%M%S` whc_sync notice msg compose on CAP:" > "$FCFG_SYNC"
    echo "$msg_decode" >> "$FCFG_SYNC"
    echo "$msg" >> "$FCFG_SYNC"
    
    local cmd="whc_sync"
    local jmsg="$msg"
    notify_re
    ret=$?
    wifi &

    return "$ret"
}

xqwhc_sync_lite()
{
    local fail=0
    local msg=""
    __info_compose

    WHC_LOGI " whc_sync_lite note msg=<\"$msg\">"
    echo "`date +%Y%m%d-%H%M%S` whc_sync_lite notice msg compose on CAP:" > "$FCFG_SYNC"
    echo "$msg_decode" >> "$FCFG_SYNC"
    echo "$msg" >> "$FCFG_SYNC"

    local cmd="whc_sync"
    local jmsg="$msg"
    notify_re
    return $?    
}

