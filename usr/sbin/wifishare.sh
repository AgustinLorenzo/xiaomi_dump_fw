#!/bin/sh
# Copyright (C) 2016 Xiaomi
. /lib/functions.sh

network_name="guest"
section_name="wifishare"
redirect_port="8999"
dev_redirect_port="8899"
whiteport_list="67 68"
http_port="80"
dns_port="53"
dnsd_port="5533"
dnsd_conf="/var/dnsd.conf"
guest_gw=$(uci get network.guest.ipaddr 2>/dev/null)
fw3lock="/var/run/fw3.lock"

hasctf=$(uci get misc.quickpass.ctf 2>/dev/null)
guest_ifname=$(uci get wireless.guest_2G.ifname 2>/dev/null)
hashwnat=$([ -f /etc/init.d/hwnat ] && echo 1)
auth_timeout_default=90
timeout_default=86400
date_tag=$(date +%F" "%H:%M:%S)
macs_blocked=""

share_block_table="wifishare_block"
share_block_table_input="wifishare_block_input"

share_whitehost_ipset="wifishare_whitehost"
share_whitehost_file="/tmp/dnsmasq.d/wifishare_whitehost.conf"

domain_white_list_file="/tmp/dnsmasq.d/wifishare_domain_list.conf"
ios_white_list_file="/tmp/dnsmasq.d/wifishare_ios_list.conf"
share_domain_ipset="wifishare_domain_list"
share_ios_ipset="wifishare_ios_list"

share_nat_table="wifishare_nat"
share_filter_table="wifishare_filter"
share_nat_device_table="wifishare_nat_device"
share_filter_device_table="wifishare_filter_device"
share_nat_dev_redirect_table="wifishare_nat_dev_redirect"

hosts_dianping=".dianping.com .dpfile.com"
hosts_apple=""
hosts_nuomi=""
hosts_index="dianping"
filepath=$(cd `dirname $0`; pwd)
filename=$(basename $0;)

daemonfile="/usr/sbin/wifishare_daemon.sh"

active="user business"
#wechat qq dianping nuomi .etc
active_type=""

WIFIRENT_NAME="wifirent"
COUNT_INTERVAL_SECS=300 #1 minites
WFSV2_flag="unchanged"
should_update_flag="false"
guest_miwifi_address="guest.miwifi.com"
guest_miwifi_dnsmasq_conf="/tmp/dnsmasq.d/guest_miwifi_dnsmasq.conf"
index_cdn_addr="http://bigota.miwifi.com/xiaoqiang/webpage/wifishare/index.html"
html_path="/etc/nginx/htdocs"
html_name="wifishare.html"

# generate random number between min & max
rand(){
    min=$1
    max=`expr $2 - $min + 1`
    rnd_num=`head -50 /dev/urandom | tr -dc "0123456789" | head -c6`
    echo `expr $rnd_num % $max + $min`
}

################### domain list #############

wifishare_log()
{
    logger -p debug -t wifishare "$1"
}

business_whitehost_add()
{
    for _host in $1
    do
        echo "ipset=/$_host/$share_whitehost_ipset" >>$share_whitehost_file
    done
}

business_init()
{
    rm $share_whitehost_file
    touch $share_whitehost_file

    for _idx in $hosts_index
    do
        _hosts=`eval echo '$hosts_'"$_idx"`
        business_whitehost_add "$_hosts"
    done
}

################### hwnat ###################
hwnat_start()
{
    [ "$hashwnat" != "1" ] && return;

uci -q batch <<-EOF >/dev/null
    set hwnat.switch.${section_name}=0
    commit hwnat
EOF
    /etc/init.d/hwnat start &>/dev/null
}

hwnat_stop()
{
    [ "$hashwnat" != "1" ] && return;

uci -q batch <<-EOF >/dev/null
    set hwnat.switch.${section_name}=1
    commit hwnat
EOF
    /etc/init.d/hwnat stop &>/dev/null
}

_locked="0"
################### lock ###################
fw3_lock()
{
    trap "lock -u $fw3lock; exit 1" SIGHUP SIGINT SIGTERM
    lock $fw3lock
    return $?
}

fw3_trylock()
{
    trap "lock -u $fw3lock; exit 1" SIGHUP SIGINT SIGTERM
    lock -n $fw3lock
    [ $? == 1 ] && _locked="1"
    return $?
}

fw3_unlock()
{
    lock -u $fw3lock
}

################### dnsd ###################
share_dnsd_start()
{

    killall dnsd > /dev/null 2>&1

    guest_gw=$(uci get network.guest.ipaddr)
    [ $? != 0 ] && return;

    #always create/update the dnsd config file (guest gw maybe changed)
    echo "* $guest_gw" > $dnsd_conf
    [ $? != 0 ] && return;

    dnsd -p $dnsd_port -c $dnsd_conf -d > /dev/null 2>&1
    [ $? != 0 ] && {
        rm $dnsd_conf > /dev/null 2>&1
        return ;
    }
}

share_dnsd_stop()
{
    killall dnsd > /dev/null 2>&1

    [ -f $dnsd_conf ] && {
        rm $dnsd_conf > /dev/null 2>&1
    }
}

################### config ###################


share_parse_global()
{
    section="$1"
    auth_timeout=""
    #timeout=""

    config_get disabled  $section disabled &>/dev/null;

    config_get auth_timeout  $section auth_timeout &>/dev/null;
    [ "$auth_timeout" == "" ] && auth_timeout=${auth_timeout_default}

    config_get timeout  $section timeout &>/dev/null;
    [ "$timeout" == "" ] && timeout=${timeout_default}

    config_get _business  $section business &>/dev/null;
    [ "$_business" == "" ] && _business=${business_default}

    config_get _sns  $section sns &>/dev/null;
    [ "$_sns" == "" ] && _sns=${sns_default}

    config_get _active  $section active &>/dev/null;
    [ "$_active" == "" ] && _active=${active_default}

    if [ "$_active" == "business" ]
    then
        active_type="$_business"
    else
        active_type="$_sns"
    fi

    #wifishare_log "active   -- $_active"
    #wifishare_log "sns      -- $_sns"
    #wifishare_log "business -- $_business"
    #wifishare_log "type     -- $active_type"
}

share_parse_block()
{
    config_get macs_blocked $section mac &>/dev/null;
}


share_ipset_create()
{
    _rule_ipset=$1
    [ "$_rule_ipset" == "" ] && return;

    ipset flush   $_rule_ipset >/dev/null 2>&1
    ipset destroy $_rule_ipset >/dev/null 2>&1
    ipset create  $_rule_ipset hash:net >/dev/null

    return
}


share_ipset_destroy()
{
    _rule_ipset=$1
    [ "$_rule_ipset" == "" ] && return;

    ipset flush   $_rule_ipset >/dev/null 2>&1
    ipset destroy $_rule_ipset >/dev/null 2>&1

    return
}

################### iptables ###################
ipt_table_create()
{
    iptables -t $1 -F $2 >/dev/null 2>&1
    iptables -t $1 -X $2 >/dev/null 2>&1
    iptables -t $1 -N $2 >/dev/null 2>&1
}

ipt_table_destroy()
{
    iptables -t $1 -F $2 >/dev/null 2>&1
    iptables -t $1 -X $2 >/dev/null 2>&1
}

################### firewall ###################
share_fw_add_default()
{
    [ "$hasctf" == "1" ] && iptables -t mangle -I PREROUTING -i br-guest  -j SKIPCTF

    ipt_table_create nat     $share_nat_table
    ipt_table_create nat     $share_nat_device_table
    ipt_table_create nat     $share_nat_dev_redirect_table
    ipt_table_create filter  $share_filter_table
    ipt_table_create filter  $share_filter_device_table

    iptables -t nat -I zone_guest_prerouting -i br-guest -j $share_nat_table >/dev/null 2>&1
    iptables -t filter -I forwarding_rule -i br-guest -j $share_filter_table >/dev/null 2>&1

    iptables -t nat -A wifishare_nat -p tcp -m tcp  --dport 80 -j REDIRECT --to-ports 8999
    #iptables -t nat -A $share_nat_table -p tcp -j REDIRECT --to-ports ${redirect_port}
    #iptables -t nat -A $share_nat_table -p udp -j REDIRECT --to-ports ${redirect_port}

    #dns redirect
    dnsd_ok="0"
#    ps | grep dnsd | grep -v grep >/dev/null 2>&1
#    [ $? == 0 ] && {
#        dnsd_ok="1"
#    }
#
#    [ "$dnsd_ok" == "1" ] && {
#        iptables -t nat -I $share_nat_table -p udp -m udp --dport ${dns_port} -j REDIRECT --to-port ${dnsd_port}
#    }

    #device list
    iptables -t filter -I $share_filter_table -j $share_filter_device_table
    iptables -t nat -I $share_nat_table -j $share_nat_device_table


    if [ "$dnsd_ok" == "0" ];
    then
        iptables -t nat -I $share_nat_dev_redirect_table -j ACCEPT
        iptables -t nat -I $share_nat_dev_redirect_table -p tcp --dst ${guest_gw} --dport ${http_port} -j REDIRECT --to-ports ${dev_redirect_port}
        iptables -t nat -I $share_nat_dev_redirect_table -p tcp -m set --match-set ${share_whitehost_ipset} dst -j ACCEPT
    else
        iptables -t nat -I $share_nat_table -p udp -m udp --dport ${dns_port} -j ACCEPT
    fi

    for _port in ${whiteport_list}
    do
        iptables -t nat -I $share_nat_table -p udp -m udp --dport ${_port} -j ACCEPT
    done



    #white host
    iptables -t filter -I $share_filter_table -p tcp -m set --match-set ${share_whitehost_ipset} dst -j ACCEPT
    iptables -t filter -I $share_filter_table -p tcp -m tcp --dport 80 -j ACCEPT
    iptables -t filter -I $share_filter_table -o br-lan -j REJECT
    iptables -t filter -A $share_filter_table -p tcp -j REJECT
    iptables -t filter -A $share_filter_table -p udp -j REJECT

    iptables -t nat -I $share_nat_table -p tcp -m set --match-set ${share_whitehost_ipset} dst -j ACCEPT
}

is_active_type()
{
#　$1 type
# $2 type list
    _type=""
    [ "$1" == "" ] && return 1;
    [ "$2" == "" ] && return 1;

    #reload
    _is_wechat_pay=$(echo $2 | grep "wifirent_wechat_pay")
    [ "$_is_wechat_pay" != "" ] && {
        [ "$1" == "$WIFIRENT_NAME" ] && return 0;
    }

    #wifishare enable
    [ "$1" == "$WIFIRENT_NAME" ] && return 0;

    for _type in $2
    do
        [ "$_type" == "$1" ] && return 0;
    done

    return 1;
}

share_fw_add_device()
{
    section="$1"
    _src_mac=""
    _start=""
    _stop=""

    config_get disabled $section disabled &>/dev/null;
    [ "$disabled" == "1" ] && return

    config_get _start $section datestart &>/dev/null;
    [ "$_start" == "" ] && return

    config_get _stop $section datestop &>/dev/null;
    [ "$_stop" == "" ] && return

    config_get _src_mac $section mac &>/dev/null;
    [ "$_src_mac" == "" ] && return

    config_get _type $section sns &>/dev/null;
    [ "$_type" == "" ] && return

    is_active_type "$_type" "$active_type" || return;

    share_block_has_mac $_src_mac
    [ $? -eq 1 ] && return

    share_access_remove $_src_mac

    iptables -t filter -A $share_filter_device_table -m mac --mac-source $_src_mac -m time --datestart $_stop --kerneltz -j DROP -m comment --comment "allow" >/dev/null 2>&1
    iptables -t filter -I $share_filter_device_table -m mac --mac-source $_src_mac -m time --datestart $_start --datestop $_stop --kerneltz -j ACCEPT -m comment --comment "allow" >/dev/null 2>&1
    iptables -t nat    -I $share_nat_device_table    -m mac --mac-source $_src_mac -m time --datestart $_start --datestop $_stop --kerneltz -j ACCEPT -m comment --comment "allow" >/dev/null 2>&1

    return;
}

share_fw_add_device_all()
{
    config_load ${section_name}

    config_foreach share_fw_add_device device

    return;
}

share_fw_remove_all()
{
    [ "$hasctf" == "1" ] && iptables -t mangle -D PREROUTING -i br-guest  -j SKIPCTF

    iptables -t nat -D zone_guest_prerouting -i br-guest -j $share_nat_table >/dev/null 2>&1

    iptables -t filter -D forwarding_rule  -i br-guest -j $share_filter_table >/dev/null 2>&1

    ipt_table_destroy nat     $share_nat_table
    ipt_table_destroy nat     $share_nat_device_table
    ipt_table_destroy nat     $share_nat_dev_redirect_table
    ipt_table_destroy filter  $share_filter_table
    ipt_table_destroy filter  $share_filter_device_table

    return
}
################### contrack ###################
share_contrack_remove_perdevice()
{
    section="$1"
    _src_mac=""
    _start=""
    _stop=""

    config_get _src_mac $section mac &>/dev/null;
    [ "$_src_mac" == "" ] && return

    share_contrack_remove $_src_mac

    return
}

share_contrack_remove_all()
{
    config_load ${section_name}

    config_foreach share_contrack_remove_perdevice device

    return
}

share_contrack_remove()
{
    _ip=$(/usr/bin/arp | awk -v mac=$1 ' BEGIN{IGNORECASE=1}{if($3==mac) print $1;}' 2>/dev/null)
    [ "$_ip" == "" ] && return

    echo $_ip > /proc/net/nf_conntrack
    return
}

################### block ###################
share_block_has_mac()
{
    _src_mac=$1
    has_mac=""

    [ "$_active" == "business" ] && return 0

    [ "$macs_blocked"  == "" ] && return 0

    has_mac=$(echo $macs_blocked | awk -v mac=$_src_mac '{for(i=1;i<=NF;i++) { if($i==mac) print "1"; break;} }')

    [ "$has_mac" != "" ] && return 1

    return 0;
}

share_block_add_default()
{
    share_block_remove_default

    ipt_table_create filter $share_block_table
    ipt_table_create filter $share_block_table_input

    iptables -t filter -I forwarding_rule -i br-guest -j $share_block_table >/dev/null 2>&1
    iptables -t filter -I INPUT -i br-guest -j $share_block_table_input >/dev/null 2>&1
    iptables -t filter -I $share_block_table_input -p tcp -m tcp --dport 8999 -j ACCEPT
}

share_block_remove_default()
{
    iptables -t filter -D forwarding_rule -i br-guest -j $share_block_table >/dev/null 2>&1
    iptables -t filter -D INPUT -i br-guest -j $share_block_table_input >/dev/null 2>&1

    ipt_table_destroy filter $share_block_table
    ipt_table_destroy filter $share_block_table_input
}

share_block_add_perdevice()
{
    section="$1"
    _src_mac=""

    config_get _mac_list $section mac &>/dev/null;

    for _src_mac in $_mac_list
    do
        name_dev="${section_name}_block_${_src_mac//:/}"

        echo "block device mac: $_src_mac, dev comment: $name_dev."

        share_access_remove $_src_mac

        iptables -t filter -A $share_block_table_input -m mac --mac-source $_src_mac -j DROP >/dev/null
        iptables -t filter -A $share_block_table -m mac --mac-source $_src_mac -j DROP >/dev/null
    done

    return;
}

share_block_apply()
{
    iptables -t filter -F $share_block_table >/dev/null 2>&1
    iptables -t filter -F $share_block_table_input >/dev/null 2>&1
    iptables -t filter -I $share_block_table_input -p tcp -m tcp --dport 8999 -j ACCEPT

    config_load ${section_name}

    config_foreach share_block_add_perdevice block
}

share_block_remove_all()
{
    iptables -t filter -F $share_block_table >/dev/null 2>&1
}

################### interface ###################
#sns : string, 社交网络代码
#guest_user_id : string, 好友id
#extra_payload : string
#mac : 放行设备mac地址
share_access_prepare()
{
    _src_mac=$1
    _device_id=""
    _current=""
    _start=""
    _stop=""
    l_timeout=$2

    [ "$_src_mac" == "" ] && return 1;

    share_block_has_mac $_src_mac
    [ $? -eq 1 ] && return

    [ "$l_timeout" == "" ] && l_timeout=auth_timeout
    [ $l_timeout -lt 30 ] && l_timeout=30
    [ $l_timeout -gt 600 ] && l_timeout=600
    _device_id=${_src_mac//:/};
    _current=$(date -u "+%Y-%m-%dT%H:%M:%S")
    _start=$(echo $_current | awk -v timeout=30 '{gsub(/-|:|T/," ",$0);now=mktime($0);now=now-timeout;print strftime("%Y-%m-%dT%H:%M:%S",now);return;}')
    _stop=$(echo $_current | awk -v timeout=$l_timeout '{gsub(/-|:|T/," ",$0);now=mktime($0);now=now+timeout;print strftime("%Y-%m-%dT%H:%M:%S",now);return;}')

    allowed_datestop=$(uci get ${section_name}.${_device_id}.datestop)
    [ "$allowed_datestop" != "" ] && {
        time_now=$(echo $_current | tr -cd '[0-9]')
        time_stop=$(echo $allowed_datestop | tr -cd '[0-9]')
        [ $time_stop -ge $time_now ]&& {
            return;
        }
    }

    name_dev="${section_name}_${_device_id}"

    share_aceess_remove_iptables $_src_mac

    dnsd_ok="0"
#    ps | grep dnsd | grep -v grep >/dev/null 2>&1
#    [ $? == 0 ] && {
#        dnsd_ok="1"
#    }

    iptables -t filter -I $share_filter_device_table -m mac --mac-source $_src_mac -m time --datestart $_stop --kerneltz -j DROP  -m comment --comment "prepare"
    iptables -t filter -I $share_filter_device_table -m mac --mac-source $_src_mac -m time --datestart $_start --datestop $_stop --kerneltz -j ACCEPT -m comment --comment "prepare"
    if [ "$dnsd_ok" == 0 ];
    then
        iptables -t nat -I $share_nat_device_table -m mac --mac-source $_src_mac -m time --datestart $_start --datestop $_stop --kerneltz -j ${share_nat_dev_redirect_table}  -m comment --comment "prepare"
    else
        iptables -t nat -I $share_nat_device_table -m mac --mac-source $_src_mac -m time --datestart $_start --datestop $_stop --kerneltz -j ACCEPT  -m comment --comment "prepare"
    fi

    return
}

share_access_prepare_status()
{
    _src_mac=$1
    _now=$(date +%s)
    _stop=$(iptables-save |grep prepare |grep wifishare_filter_device |grep "$_src_mac" |awk '{gsub(/-|:|T/," ",$10);now=mktime($10);print now;return;}')

    [ "$_stop" == "" ] && {
        echo "no rule"
        return 1
    }

    [ $_now -lt $_stop ] && {
        echo "prepared"
        return 0
    }

    [ $_now -ge $_stop ] && {
        echo "timeout"
        return 2
    }

    return 3
}
check_local_config()
{
    _domain_white_list=$(uci get wifishare.global.domain_white_list 2>/dev/null)
    _ios_domain=$(uci get wifishare.global.ios_domain 2>/dev/null)
    _update_cfg_time=$(uci get wifishare.global.update_cfg_time 2>/dev/null)
    _config_md5=$(uci get wifishare.global.config_md5 2>/dev/null)
    [ -z "${_update_cfg_time}" ] && {
        _time_now=`date +%s`
        uci set wifishare.global.update_cfg_time="${_time_now}"
        uci commit wifishare
    }
    [ -z "${_config_md5}" ] && {
        uci set wifishare.global.config_md5="12345"
        should_update_flag="true"
        uci commit wifishare
    }
    [ -z "${_domain_white_list}" ] && {
        uci set wifishare.global.domain_white_list="s.miwifi.com api.miwifi.com"
        uci commit wifishare
        should_update_flag="true"
    }
    [ -z "${_ios_domain}" ] && {
        uci set wifishare.global.ios_domain="captive.apple.com"
        uci commit wifishare
        should_update_flag="true"
    }
}

update_server_config(){
    check_local_config
    _time_now=`date +%s`
    _time_to_run=`uci get wifishare.global.update_cfg_time`
    _diff=`expr ${_time_now} - ${_time_to_run}`
    if [ "${_diff}" -ge "-${COUNT_INTERVAL_SECS}" ] || [ "${_diff}" -le "-129600" ]; then
        get_server_config
        time_stamp_init
    fi
}

get_server_config(){
    check_local_config
    config_md5_file="/tmp/wifishare_conf_md5.json"
    # if server is not reachable, use local config
    if ! (curl --connect-timeout 2 http://api.miwifi.com/data/wifishare/config/md5 > ${config_md5_file}) ; then
        echo "cannot get server config md5, use local config, do not update"
    fi
    config_json_md5=`cat ${config_md5_file}`
    config_uci_md5=`uci get wifishare.global.config_md5`
    if [ "${config_json_md5}" = "${config_uci_md5}" ] ; then
        # md5 is the same, server config is not changed
        echo "server config md5 is the same with local config md5, do not update"
    else
        # md5 is not the same, should update config
        should_update_flag="true"
    fi
    if [ "${should_update_flag}" = "false" ] ; then
        return 0
    fi
    config_json_file="/tmp/wifishare_conf.json"
    logger -p info -t wifishare "stat_points_none wifishare_get_config_from_server=$date_tag"
    if ! (curl --connect-timeout 2 http://api.miwifi.com/data/wifishare/config > ${config_json_file}) ; then
        echo "cannot get server config content, use local config, do not update"
    fi
    # use jshn lib in openwrt to phase json
    source /usr/share/libubox/jshn.sh
    json_content=$(cat ${config_json_file})
    json_load "${json_content}"
    json_get_var server_domain_white_list domain_white_list
    json_get_var server_ios_domain ios_domain

    local_domain_white_list=$(uci get wifishare.global.domain_white_list 2>/dev/null)
    local_ios_domain=$(uci get wifishare.global.ios_domain 2>/dev/null)

    if [ -n "${server_domain_white_list}" ] && [ "${server_domain_white_list}" != "${local_domain_white_list}" ] ; then
        uci set wifishare.global.domain_white_list="${server_domain_white_list}"
        WFSV2_flag="changed"
    fi
    if [ -n "${server_ios_domain}" ] && [ "${server_ios_domain}" != "${local_ios_domain}" ] ; then
        uci set wifishare.global.ios_domain="${server_ios_domain}"
        WFSV2_flag="changed"
    fi
    if [ -n "${config_json_md5}" ] ; then
        uci set wifishare.global.config_md5="${config_json_md5}"
    fi
    uci commit wifishare
    rm ${config_json_file}
    if [ "${WFSV2_flag}" = "changed" ] ; then
        domain_allow_init
    fi
}

domain_allow_init(){
    local_domain_white_list=$(uci get wifishare.global.domain_white_list 2>/dev/null)
    local_ios_domain=$(uci get wifishare.global.ios_domain 2>/dev/null)
    # create ipsets
    share_ipset_create ${share_domain_ipset}
    share_ipset_create ${share_ios_ipset}
    # add dnsmasq file
    rm -f ${domain_white_list_file} ${ios_white_list_file} ${guest_miwifi_dnsmasq_conf} > /dev/null 2>&1
    touch ${domain_white_list_file} ${ios_white_list_file} ${guest_miwifi_dnsmasq_conf}
    for _host1 in ${local_domain_white_list} ; do
        echo "ipset=/!${_host1}/${share_domain_ipset}" >> ${domain_white_list_file}
    done
    for _host2 in ${local_ios_domain} ; do
        echo "ipset=/!${_host2}/${share_ios_ipset}" >> ${ios_white_list_file}
    done

    # refresh guest gw always, avoid guest_miwifi_dnsmasq.conf != guest ip.
    #wifishare_log "old guest_gw :  ${guest_gw}"
    guest_gw=$(uci get network.guest.ipaddr)
    #wifishare_log "new guest_gw :  ${guest_gw}"

    if [ -n "${guest_gw}" ] ; then
        echo "address=/${guest_miwifi_address}/${guest_gw}" >> ${guest_miwifi_dnsmasq_conf}
    fi
    /etc/init.d/dnsmasq restart

    # add iptable rules
    _domain_nat_count=`iptables-save -t nat | grep ${share_domain_ipset} | wc -l`
    if [ "${_domain_nat_count}" -eq 0 ] ; then
        iptables -t nat -I ${share_nat_table} -m set --match-set ${share_domain_ipset} dst -j ACCEPT >/dev/null 2>&1
    fi
    _domain_filter_count=`iptables-save -t filter | grep ${share_domain_ipset} | wc -l`
    if [ "${_domain_filter_count}" -eq 0 ] ; then
        iptables -t filter -I ${share_filter_table} -m set --match-set ${share_domain_ipset} dst -j ACCEPT >/dev/null 2>&1
    fi
    logger -p info -t wifishare "stat_points_none wifishare_domain_allow_init=$date_tag"
}

ios_portal_allow(){
    _src_mac=$1
    if [ "${_src_mac}" = "" ] ; then
        echo 1 # no mac, error code 1
        return
    fi
    # change mac to upper case
    _src_mac=`echo ${_src_mac} | tr [a-f] [A-F]`
    # remove old firewall rule
    _old_nat_entry=`iptables-save -t nat | grep ${share_ios_ipset} | grep "${_src_mac}" | sed 's/-A /-D /'`
    [ -n "${_old_nat_entry}" ] && iptables -t nat ${_old_nat_entry} >/dev/null 2>&1
    _old_filter_entry=`iptables-save -t filter | grep ${share_ios_ipset} | grep "${_src_mac}" | sed 's/-A /-D /'`
    [ -n "${_old_filter_entry}" ] && iptables -t filter ${_old_filter_entry} >/dev/null 2>&1
    # add new firewall rule
    _ios_timeout=`uci get wifishare.global.auth_timeout`
    date_start_stamp=`date +%s`
    date_stop_stamp=`expr ${date_start_stamp} + ${_ios_timeout}`
    _date_start=`date -u +%Y-%m-%dT%T -d @"$date_start_stamp"`
    _date_stop=`date -u +%Y-%m-%dT%T -d @"$date_stop_stamp"`
    iptables -t nat -I ${share_nat_device_table} -m mac --mac-source ${_src_mac} -m time --datestart ${_date_start} --datestop ${_date_stop} -m set --match-set ${share_ios_ipset} dst -j ACCEPT >/dev/null 2>&1
    _result_nat=$?
    [ "${_result_nat}" != "0" ] && echo 2 && return
    iptables -t filter -I ${share_filter_device_table} -m mac --mac-source ${_src_mac} -m time --datestart ${_date_start} --datestop ${_date_stop} -m set --match-set ${share_ios_ipset} dst -j ACCEPT >/dev/null 2>&1
    _result_filter=$?
    [ "${_result_filter}" != "0" ] && echo 2 && return
    echo 0 # success
}


share_access_allow()
{
    _src_mac=$1
    dev_sns=$2
    l_timeout=$3
    _device_id=""
    _start=""
    _stop=""

    force_write=0
    online_time=$(ubus call trafficd hw '{"hw":"'$_src_mac'"}' | grep online_timer |awk '{print $2}'|sed 's/,//g')

    [ "$_src_mac" == "" ] && return 1;

    share_block_has_mac $_src_mac
    [ $? -eq 1 ] && return

    _device_id=${_src_mac//:/};
    _current=$(date -u "+%Y-%m-%dT%H:%M:%S")
    _start=$(date -u "+%Y-%m-%dT%H:%M:%S")
    echo "local $l_timeout timeout $timeout"
    [ "$l_timeout" == "" ] && l_timeout=$timeout
    echo "local $l_timeout timeout $timeout"

    _stop=$(echo $_start | awk -v timeout=$l_timeout '{gsub(/-|:|T/," ",$0);now=mktime($0);now=now+timeout;print strftime("%Y-%m-%dT%H:%M:%S",now);return;}')
    allowed_datestop=$(uci get ${section_name}.${_device_id}.datestop)
    _payload=$(uci get ${section_name}.${_device_id}.extra_payload)

    force_write=$(is_active_type "$_type" "$active_type")
    #logger -p warn -t wifishare "force_write $force_write $dev_sns active $active_type"
    [ "$allowed_datestop" != "" -a "$force_write" == "0" ] && {
        time_now=$(echo $_current | tr -cd '[0-9]')
        time_stop=$(echo $allowed_datestop | tr -cd '[0-9]')
        [ $time_stop -ge $time_now ]&& {
            return;
        }
    }

    share_aceess_remove_iptables $_src_mac

    iptables -t filter -I $share_filter_device_table -m mac --mac-source $_src_mac -m time --datestart $_stop --kerneltz -j DROP -m comment --comment "allow"
    iptables -t filter -I $share_filter_device_table -m mac --mac-source $_src_mac -m time --datestart $_start --datestop $_stop --kerneltz -j ACCEPT -m comment --comment "allow"
    exe_ret1=$?
    iptables -t nat    -I $share_nat_device_table -m mac --mac-source $_src_mac -m time --datestart $_start --datestop $_stop --kerneltz -j ACCEPT -m comment --comment "allow"
    exe_ret2=$?

    [ "$exe_ret1" != "0" ] && logger -p info -t wifishare "stat_points_none wifishare_error=$_src_mac|iptables_add1|$date_tag|$exe_ret1"
    [ "$exe_ret2" != "0" ] && logger -p info -t wifishare "stat_points_none wifishare_error=$_src_mac|iptables_add2|$date_tag|$exe_ret2"

uci -q batch <<-EOF >/dev/null
    set ${section_name}.${_device_id}=device
    set ${section_name}.${_device_id}.datestart="$_start"
    set ${section_name}.${_device_id}.datestop="$_stop"
    set ${section_name}.${_device_id}.mac="$_src_mac"
    set ${section_name}.${_device_id}.timecount_last="$online_time"
EOF
    uci commit ${section_name}

    # just call jason.sh for node has initial_ticket, save 90ms
    has_ticket=$(echo $_payload | grep "\[\"initial_ticket\"\]");
    if [ "$has_ticket" != "" ]
    then
        old_ticket=$(echo $_payload | jason.sh -b |grep "\[\"initial_ticket\"\]" |awk '{print $2}' |sed 's/\"//g');
        [ "$old_ticket" != "" ] && logger -p info -t wifishare "stat_points_none wifishare_allow=$_src_mac|$old_ticket|$date_tag";
        [ "$old_ticket" == "" ] && logger -p info -t wifishare "stat_points_none wifishare_error=$_src_mac|nooldticket|$date_tag";
    else
        logger -p info -t wifishare "stat_points_none wifishare_error=$_src_mac|nooldticket|$date_tag";
    fi
}

share_aceess_remove_iptables()
{
    _src_mac=$1
    _device_id=""

    [ "$_src_mac" == "" ] && return 1;

    _device_id=${_src_mac//:/};

#    iptables -t filter -A $share_filter_table -m mac --mac-source $_src_mac -m time --datestart $_stop --kerneltz -m comment --comment ${name_dev} -j DROP
iptables-save -t filter | awk -v mac=$_src_mac '/^-A wifishare_filter_device /  {
    i = 1;
    while ( i <= NF )
    {
        if($i~/--mac-source/)
        {
            if($(i+1)==mac)
            {
                gsub("^-A", "-D")
                print "iptables -t filter "$0";"
            }
        }
        i++
    }
}' |sh

iptables-save -t nat | awk -v mac=$_src_mac  '/^-A wifishare_nat_device / {
    i = 1;
    while ( i <= NF )
    {
        if($i~/--mac-source/)
        {
            if($(i+1)==mac)
            {
                gsub("^-A", "-D")
                print "iptables -t nat "$0";"
            }
        }
        i++
    }
}' |sh

   return;
}

share_access_remove()
{
    _src_mac=$1

    share_aceess_remove_iptables $_src_mac

    share_contrack_remove $_src_mac

    logger -p info -t wifishare "stat_points_none wifishare_remove=$_src_mac|$date_tag"
    return
}

timeout_devname_list=""
current_time=""
share_timeout_gettime()
{
   current_time=$(echo 1|   awk '{now=systime(); print now }')
}

share_access_timeout_iptables()
{
    rm /tmp/wifishare_timeout_mac
    current_utc_time=$(date -u "+%Y-%m-%dT%H:%M:%S" @${current_time})
    current_utc_time=$(echo $current_utc_time | awk '{gsub(/-|:|T/," ",$0);print $0}')
    current_utc_time_sec=$(echo $current_utc_time | awk '{sec=mktime($0);print sec}')

iptables-save -t nat | awk -v  now=$current_utc_time_sec -v auth_timeout=$auth_timeout '/^-A wifishare_nat_device / {
    i = 1;
    while ( i <= NF )
    {
        if($i~/--mac-source/)
        {
            need_remove=0;
            mac=$(i+1);
            device_id=mac;
            gsub(":", "", device_id);
        }

        if($i~/--datestart/)
        {
            datestart_ori=$(i+1)
            datestart=$(i+1)
            gsub(/-|:|T/," ", datestart);
            start=mktime(datestart);
        }

        if($i~/--comment/)
        {
            comment_ori=$(i+1)
        }

        if($i~/--datestop/)
        {
            datestop=$(i+1);
            datestop_ori=$(i+1);
            filter_datestart=datestop;
            gsub(/-|:|T/," ", datestop);
            stop=mktime(datestop);
            if(now>stop)
            {
                need_remove=1;
            }
        }

        if($i~/-j/)
        {
            if(need_remove == 1)
            {
                gsub("^-A", "-D");
                print "iptables -t filter -D wifishare_filter_device -m mac --mac-source "mac" -m time --datestart "filter_datestart" --kerneltz -m comment --comment "comment_ori" -j DROP";
                print "iptables -t filter -D wifishare_filter_device -m mac --mac-source "mac" -m time --datestart "datestart_ori" --datestop "datestop_ori" --kerneltz -m comment --comment "comment_ori" -j ACCEPT";
                print "iptables -t nat "$0;
                print "logger -p info -t wifishare \"stat_points_none wifishare_timeout="mac"|"datestop"|"now"\""
                print "echo "mac" > /tmp/wifishare_timeout_mac"
            }
        }

        i++
    }
} ' |sh

iptables-save -t filter | TZ=UTC awk -v  now=$current_utc_time_sec '/^-A wifishare_filter_device / {
    i = 1;
    while ( i <= NF )
    {
        if($i~/--mac-source/)
        {
            need_remove=0;
            mac=$(i+1);
        }

        if($i~/--datestart/)
        {
            datestart=$(i+1)
            gsub(/-|:|T/," ", datestart);
            start=mktime(datestart);
        }

        if($i~/--datestop/)
        {
            datestop=$(i+1);
            gsub(/-|:|T/," ", datestop);
            stop=mktime(datestop);
            if(now>stop)
            {
                need_remove=1;
            }
        }

        if($i~/-j/)
        {
            if(need_remove == 1)
            {
                gsub("^-A", "-D");
                print "iptables -t filter "$0;
                print "logger -p info -t wifishare \"stat_points_none wifishare_ios_timeout="mac"|"datestop"|"now"\""
            }
        }
        i++
    }
} ' |sh

    macsets_timeout=$(cat /tmp/wifishare_timeout_mac)
    [ "$macsets_timeout" != "" ] && {
        for onemac in $macsets_timeout
        do
           share_contrack_remove ${onemac}
        done
    }
    rm /tmp/wifishare_timeout_mac
    return
}

share_record_timeout_perdevice()
{
    _mac=""
    _datestop=""
    _stop=""
    _start=""

    need_remove=0

    config_get _mac $section mac &>/dev/null;
    config_get _timestamp $section timestamp &>/dev/null;

    _start_timeout
    let _start_timeout=$current_time-$_timestamp

    echo $_start_timeout
    [  $_start_timeout -gt $timeout_range ] && {
        macsets_timeout="$macsets_timeout $_mac"
    }

}

share_record_timeout()
{
    macsets_timeout=""

    onemac=""
    config_load "${section_name}"

    [ -z $timeout_range ] && timeout_range=$timeout
    [ "$timeout_range" -le 3600 ] && timeout_range=3600

    config_foreach share_record_timeout_perdevice record

    [ "$macsets_timeout" != "" ] && {
        for onemac in $macsets_timeout
        do
           _device_id=""
            _device_id=${onemac//:/}
            uci delete ${section_name}.${_device_id}"_RECORD"
            uci delete ${section_name}.${_device_id}"_RECORD1"
            uci delete ${section_name}.${_device_id}"_RECORD2"
            uci delete ${section_name}.${_device_id}"_RECORD3"
        done
        uci commit ${section_name}
    }
}


share_access_timeout_config_perdevice()
{
    _mac=""
    _datestop=""
    _stop=""
    _start=""

    need_remove=0

    config_get _mac $section mac &>/dev/null;
    config_get _datestop $section datestop &>/dev/null;
    config_get _datestart $section datestart &>/dev/null;

    _stop=$(echo $_datestop |awk '{gsub(/-|:|T/," ", $O); seconds=mktime($0); print seconds;}')
    _start=$(echo $_datestart |awk '{gsub(/-|:|T/," ", $O); seconds=mktime($0); print seconds;}')

    [ $_stop -lt $current_time ] && {
        need_remove=1;
    }

    [ "$need_remove" == "1" ] && {
        macsets_timeout="$macsets_timeout $_mac"
    }
}

share_access_timeout_uci()
{
    macsets_timeout=""
    onemac=""
    config_load "${section_name}"


    config_foreach share_access_timeout_config_perdevice device

    [ "$macsets_timeout" != "" ] && {
        for onemac in $macsets_timeout
        do
           _device_id=""
            _device_id=${onemac//:/}
            share_contrack_remove ${onemac}
            uci delete ${section_name}.${_device_id}
        done
        uci commit ${section_name}
    }
}



share_access_timeout()
{
    #get current time
    share_timeout_gettime

    #remove iptables
    share_access_timeout_iptables

    share_access_timeout_uci

    share_record_timeout
    return
}


share_clean_config_perdevice_wifirent()
{
    _mac=""
    #_sns=""

    config_get _mac $section mac &>/dev/null;

    macsets_cleaned="$macsets_cleaned $_mac"
}


share_clean_wifirent()
{
    macsets_cleaned=""

    config_load "${section_name}"

    config_foreach share_clean_config_perdevice_wifirent device

    [ "$macsets_cleaned" != "" ] && {
        for onemac in $macsets_cleaned
        do
           _device_id=""
            _device_id=${onemac//:/}
            share_contrack_remove ${onemac}
            uci delete ${section_name}.${_device_id}
        done
        uci commit ${section_name}
    }
}


share_clean_config_perdevice()
{
    _mac=""
    dev_sns=""

    config_get _mac $section mac &>/dev/null;
    config_get dev_sns $section sns &>/dev/null;
    [ "$dev_sns" == "$WIFIRENT_NAME" ] && return;

    macsets_cleaned="$macsets_cleaned $_mac"
}


share_clean_uci_device()
{
    macsets_cleaned=""

    config_load "${section_name}"

    config_foreach share_clean_config_perdevice device

    [ "$macsets_cleaned" != "" ] && {
        for onemac in $macsets_cleaned
        do
           _device_id=""
            _device_id=${onemac//:/}
            #share_contrack_remove ${onemac}
            share_access_remove ${onemac}
            uci delete ${section_name}.${_device_id}
        done
        uci commit ${section_name}
    }
}

share_clean_uci_record()
{
    macsets_cleaned=""

    config_load "${section_name}"

    config_foreach share_clean_config_perdevice record

    [ "$macsets_cleaned" != "" ] && {
        for onemac in $macsets_cleaned
        do
           _device_id=""
            _device_id=${onemac//:/}
            share_contrack_remove ${onemac}
            uci delete ${section_name}.${_device_id}"_RECORD"
            uci delete ${section_name}.${_device_id}"_RECORD1"
            uci delete ${section_name}.${_device_id}"_RECORD2"
            uci delete ${section_name}.${_device_id}"_RECORD3"
        done
        uci commit ${section_name}
    }
}

share_clean_uci_block()
{
    uci delete ${section_name}.blacklist
    uci commit ${section_name}
}

share_clean()
{
    iptables -t nat -F $share_nat_device_table >/dev/null 2>&1
    #iptables -t nat -F $share_nat_dev_redirect_table >/dev/null 2>&1
    iptables -t filter -F $share_filter_device_table >/dev/null 2>&1
    iptables -t filter -F $share_block_table >/dev/null 2>&1
    iptables -t filter -F $share_block_table_input >/dev/null 2>&1
    iptables -t filter -I $share_block_table_input -p tcp -m tcp --dport 8999 -j ACCEPT

    share_clean_uci_device

    share_clean_uci_record

    share_clean_uci_block

    share_fw_add_device_all
    return;
}


share_reload()
{
    # add guest ip calc when router reboot(wifishare reload)
    guest_ip_check

    share_fw_remove_all

    share_ipset_create $share_whitehost_ipset

    [ "$_active" == "business" ] && business_init

    [ "$_active" == "business" ] && share_dnsd_start

    share_fw_add_default

    share_fw_add_device_all

    share_block_remove_default

    share_block_add_default

    [ "$_active" != "business" ] && share_block_apply

    get_server_config
    # make sure to init domain allow once at least
    if [ "${WFSV2_flag}" = "unchanged" ] ; then
        domain_allow_init
    fi

    # update wifishare anyway
    curl ${index_cdn_addr} -o ${html_path}"/"${html_name} &

    return
}

share_config_set()
{
    _auth_timeout=${1}
    _timeout=${2}
    _dhcp_leasetime=${3}

    [ ! -z $_dhcp_leasetime ] && {
uci -q batch <<-EOF >/dev/null
    set dhcp.guest.leasetime=${_dhcp_leasetime}
EOF
    uci commit dhcp
    /etc/init.d/dnsmasq restart
}

uci -q batch <<-EOF >/dev/null
    set firewall.${section_name}=include
    set firewall.${section_name}.path="/usr/sbin/wifishare.sh reload"
    set firewall.${section_name}.reload=1
    set ${section_name}.global.auth_timeout=${_auth_timeout}
    set ${section_name}.global.timeout=${_timeout}
EOF

    uci commit firewall
    uci commit ${section_name}

    return;
}

share_config_set_default()
{
uci -q batch <<-EOF >/dev/null
    del firewall.${section_name}
    set ${section_name}.global.auth_timeout=${auth_timeout_default}
    set dhcp.guest.leasetime=2h
EOF

    uci commit ${section_name}
    uci commit dhcp
    uci commit firewall

    /etc/init.d/dnsmasq restart

}

share_start()
{

    name_default="${section_name}_default"
    _auth_timeout=${1}
    _dhcp_leasetime=${3}

    has_wifishare=$(uci get firewall.wifishare.path)

    [ "$has_wifishare" == "/usr/sbin/wifishare.sh reload" ]  && return

    [ -z $_auth_timeout ] && _auth_timeout=${auth_timeout_default}

    share_reload

    share_config_set $@

    return
}

share_stop()
{
    share_config_set_default

    share_contrack_remove_all

    share_fw_remove_all

    share_block_remove_all

    share_block_remove_default

    share_ipset_destroy $share_whitehost_ipset

    share_ipset_destroy ${share_domain_ipset}

    share_ipset_destroy ${share_ios_ipset}

    share_dnsd_stop

    share_clean

    return
}

guest_ip_check()
{
    guest_ip="$(uci get network.guest.ipaddr 2>/dev/NULL)"
    lan_ip="$(uci get network.lan.ipaddr 2>/dev/NULL)"
    new_ip="$(lua /usr/sbin/guestwifi_mkip.lua "$lan_ip")"

    if [ "$guest_ip" != "$new_ip" ];then
        echo "IP conflict, calc new guest ip "$new_ip
    fi
}

guest_network_judge()
{
    _encryption=$(uci get wireless.guest_2G.encryption 2>/dev/null)
    _ssid=$(uci get wireless.guest_2G.ssid 2>/dev/null)
    _disabled=$(uci get wireless.guest_2G.disabled 2>/dev/null)
    _passwd=$(uci get wireless.guest_2G.key 2>/dev/null)
    [ "$_disabled" == 1 ] && exit 1
    [ "$_ssid" == "" ] && exit 1
    # check guest ip conflict
    guest_ip_check

    # for different guest mode    
    [ "$_encryption" != "none" ] && exit 1
    # wifishare_log "passwd  ===== $_passwd"
    # for guest wifi not share
    [ "$_passwd" == "12345678" ] && [ "$_encryption" == "none" ] && exit 1


    return
}

share_usage()
{
    echo "$0:"
    echo "    on     : start guest share, guest must open and encryption is none."
    echo "        format: $0 on auth_timeout timeout"
    echo "                auth_timeout default 60 seconds(one minute). "
    echo "                timeout default 86400 second(one day)"
    echo "                dhcp_leasetime default 2h (2 hour). other example 60m"
    echo "        eg: $0 on"
    echo "        eg: $0 on 120 7200 2h"
    echo "    off    : stop guest share."
    echo "        format: $0 off"
    echo "    block_apply: apply block list."
    echo "        format: $0 block_apply"
    echo "    prepare: prepare for guest client, allow data transfer for 60 seconds."
    echo "        format: $0 prepare mac_address timeouts"
    echo "        eg    : $0 prepare 01:12:34:ab:cd:ef"
    echo "    allow  : access allow, default 1 day."
    echo "        format: $0 allow mac_address"
    echo "        eg    : $0 allow 01:12:34:ab:cd:ef"
    echo "    deny   : access deny, default 1 day."
    echo "        format: $0 deny mac_address"
    echo "        eg    : $0 deny 01:12:34:ab:cd:ef"
    echo "    timeout: remove timeout item in firewall iptables wifishare."
    echo "        format: $0 timeout"
    echo "    other: usage."

    return;
}

daemon_stop()
{
    this_pid=$$
    one_pid=""
    _pid_list=""
    echo $$ >/tmp/wifishare_deamon.pid

    ps w|grep wifishare_daemon.sh|grep -v grep

    _pid_list=$(ps w|grep wifishare_daemon.sh|grep -v grep |grep -v counting|awk '{print $1}')
    for one_pid in $_pid_list
    do
        echo "curent try pid "$one_pid" end"
        [ "$one_pid" != "$this_pid" ] && {
            echo "wifishare kill "$one_pid
            kill -9 $one_pid
        }
    done
    echo "wifishare daemon stop"
}

daemon_start()
{
    daemon_stop
    $daemonfile daemon &
}

daemon_run()
{
    sleep 60
    time_stamp_init
    time_stamp_html_init
    while true
    do
        $daemonfile timeout
        $daemonfile update_cfg
        $daemonfile update_html
        sleep $COUNT_INTERVAL_SECS
    done
}

# get current time and calculate next update config time
time_stamp_init(){
    _init_time_stamp=`date +%s`
    _random_interval=`rand 43200 129600`
    _next_time=`expr ${_init_time_stamp} + ${_random_interval}`
    uci set wifishare.global.update_cfg_time=${_next_time}
    uci commit wifishare
}

time_stamp_html_init()
{
    #update wifishare.html from cdn every 2-4h
    _init_time_stamp=`date +%s`
    _random_interval=`rand 7200 14400`
    _next_time=`expr ${_init_time_stamp} + ${_random_interval}`
    uci set wifishare.global.update_wifishare_html_time=${_next_time}
    uci commit wifishare
}

get_wifishare_html_cdn()
{
    #set -x
    last_etag=`uci get wifishare.global.last_etag`
    get_url="curl -I ${index_cdn_addr} -m 5 --connect-timeout 5 -s --header If-None-Match:\"${last_etag}\""
    result_code=`${get_url} -w %{http_code} -o /dev/null`
    if [ "x${result_code}" == "x304" ];then
        wifishare_log "get cdn wifishare.html http code is 304, at date:$date_tag"
        return
    fi

    if [ "x${result_code}" == "x200" ];then
      if [ ! -d "$html_path" ];then
          mkdir $html_path
      fi

      curl ${index_cdn_addr} -o ${html_path}"/"${html_name}
      [ $? != 0 ] && {
          wifishare_log "curl get cdn wifishare.html error, at date:$date_tag"
          return
      }

      # update etag only when curl OK !
      get_etag=`${get_url} | grep "ETag" | cut -d "\"" -f 2`
      uci set wifishare.global.last_etag=$get_etag
      uci commit wifishare
      logger -p info -t wifishare "stat_points_none wifishare_update_html_from_cdn=$date_tag"
    fi
}

update_wifishare_html_cdn()
{
    _time_now=`date +%s`
    _time_to_run=`uci get wifishare.global.update_wifishare_html_time`
    if [ x$_time_to_run == x ];then
        _time_to_run=0
    fi
    _diff=`expr ${_time_now} - ${_time_to_run}`
    #echo $_diff
    if [ "${_diff}" -ge "-${COUNT_INTERVAL_SECS}" ] || [ "${_diff}" -le "-14400" ]; then
        get_wifishare_html_cdn
        time_stamp_html_init
    fi
}

OPT=$1

config_load "${section_name}"

config_foreach share_parse_global global

config_foreach share_parse_block block
#main
wifishare_log "$OPT"

case $OPT in
    on)

        guest_network_judge

        #hwnat_stop

        fw3_lock
        share_start $2 $3 $4
        fw3_unlock

        daemon_start
        # 1. do wanip check
        /usr/sbin/wanip_check.sh on & >/dev/null 2>&1
        # 2. start security check deamon
        /usr/sbin/security_check.sh on & >/dev/null 2>&1

        return $?
    ;;

    off)
        fw3_lock
        share_stop
        fw3_unlock

        #hwnat_start

        daemon_stop
        # stop wanip & security check deamon
        /usr/sbin/wanip_check.sh off & >/dev/null 2>&1
        /usr/sbin/security_check.sh off &>/dev/null 2>&1
        return $?
    ;;

    prepare)
        _dev_mac=$(echo "$2"| tr '[a-z]' '[A-Z]')
        fw3_lock
        wifishare_log "$OPT begin"
        share_access_prepare $_dev_mac $3
        #share_access_timeout

        wifishare_log "$OPT end"
        fw3_unlock
        return $?
    ;;

    pstatus)
        ret_code=0
        _dev_mac=$(echo "$2"| tr '[a-z]' '[A-Z]')
        share_access_prepare_status $_dev_mac
        return $?
    ;;

    allow)
        _dev_mac=$(echo "$2"| tr '[a-z]' '[A-Z]')
        _dev_sns="$3"
        fw3_lock
        wifishare_log "$OPT begin"
        share_access_allow $_dev_mac $_dev_sns $4
        share_access_timeout
        wifishare_log "$OPT end"
        fw3_unlock
        return $?
    ;;

    deny)
        #deny issue don't delete uci config
        _dev_mac=$(echo "$2"| tr '[a-z]' '[A-Z]')
        fw3_trylock
        wifishare_log "$OPT begin"
        [ "$_locked" == "1" ] && return;
        share_access_remove $_dev_mac
        share_access_timeout
        wifishare_log "$OPT end"
        fw3_unlock
        return $?
    ;;

    block_apply)
        fw3_trylock
        [ "$_locked" == "1" ] && return;
        share_block_apply
        fw3_unlock
        return $?
    ;;

    daemon)
        daemon_run
    ;;

    update_cfg)
        update_server_config
    ;;

    timeout)
        _timeout=$(echo $2 | sed 's/[^0-9]//g')
        fw3_trylock
        share_access_timeout
        fw3_unlock
        return $?
    ;;

    clean)
        fw3_trylock
        [ "$_locked" == "1" ] && return;
        wifishare_log "$OPT begin"
        share_clean
        #share_clean_wifirent
        wifishare_log "$OPT end"
        fw3_unlock
        logger -p info -t wifishare "stat_points_none wifishare_clean=$date_tag"
    ;;

    reload)
        wifishare_log "$OPT begin"
        share_reload
        daemon_start
        wifishare_log "$OPT end"

        # 1. start security check deamon, for router startup when guest wifi open.
        /usr/sbin/security_check.sh on & >/dev/null 2>&1
        return $?
    ;;

    iosready)
        wifishare_log "$OPT begin"
        fw3_trylock
        ios_portal_allow $2
        fw3_unlock
        wifishare_log "$OPT end"
        return $?
    ;;

    update_html)
        update_wifishare_html_cdn
    ;;

    *)
        share_usage
        return 0
    ;;
esac

