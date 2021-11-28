#!/bin/sh

redundancy_mode=`uci get misc.log.redundancy_mode`
LOG_TMP_MEMINFO="/tmp/meminfo.log"
LOG_TMP_FILE_PATH="/tmp/xiaoqiang.log"
LOG_ZIP_FILE_PATH="/tmp/log.tar.gz"

WIRELESS_FILE_PATH="/etc/config/wireless"
WIRELESS_STRIP='/tmp/wireless.conf'
NETWORK_FILE_PATH="/etc/config/network"
NETWORK_STRIP="/tmp/network.conf"
MACFILTER_FILE_PATH="/etc/config/macfilter"
CRONTAB="/etc/crontabs/root"
NVRAM_FILE_PATH="/tmp/nvram.txt"
BDATA_FILE_PATH="/tmp/bdata.txt"

LOG_DIR="/data/usr/log/"
LOGREAD_FILE_PATH="/data/usr/log/messages"
LOG_WIFI_AYALYSIS="/data/usr/log/wifi_analysis.log"
LOG_WIFI_AYALYSIS0="/data/usr/log/wifi_analysis.log.0.gz"
PANIC_FILE_PATH="/data/usr/log/panic.message"
TMP_LOG_FILE_PATH="/tmp/messages"
TMP_WIFI_LOG_ANALYSIS="/tmp/wifi_analysis.log"
TMP_WIFI_LOG="/tmp/wifi.log"
DHCP_LEASE="/tmp/dhcp.leases"
IPTABLES_SAVE="/tmp/iptables_save.log"
TRAFFICD_LOG="/tmp/trafficd.log"
PLUGIN_LOG="/tmp/plugin.log"
LOG_MEMINFO="/proc/meminfo"
DNSMASQ_CONF="/var/etc/dnsmasq.conf.cfg01411c"
QOS_CONF="/etc/config/miqos"
WIFISHARE_CONF="/etc/config/wifishare"
MICLOUD_LOG="/tmp/micloudBackup.log"
WHC_LOG="/tmp/whc.log"   ### for D01/RM1800/R3600 xqwhc
GZ_LOGS=""

hardware=`uci get /usr/share/xiaoqiang/xiaoqiang_version.version.HARDWARE`

# $1 plugin install path
# $2 output file path
list_plugin(){
    for file in `ls $1 | grep [^a-zA-Z]\.manifest$`
    do
        if [ -f $1/$file ];then
            status=$(grep -n "^status " $1/$file | cut -d'=' -f2 | cut -d'"' -f2)
            plugin_id=$(grep "name" $1/$file | cut -d'=' -f2 | cut -d'"' -f2)
            if [ "$status"x = "5"x ]; then
		echo "$plugin_id" >> $2 # eanbled
        fi
        fi
    done
}

rm -f $LOG_TMP_FILE_PATH

cat $TMP_LOG_FILE_PATH >> $LOGREAD_FILE_PATH
> $TMP_LOG_FILE_PATH

cat $TMP_WIFI_LOG_ANALYSIS >> $LOG_WIFI_AYALYSIS
> $TMP_WIFI_LOG_ANALYSIS

echo "==========SN" >> $LOG_TMP_FILE_PATH
nvram get SN >> $LOG_TMP_FILE_PATH

echo "==========uptime" >> $LOG_TMP_FILE_PATH
uptime >> $LOG_TMP_FILE_PATH

echo "==========df -h" >> $LOG_TMP_FILE_PATH
df -h >> $LOG_TMP_FILE_PATH

echo "==========bootinfo" >> $LOG_TMP_FILE_PATH
bootinfo >> $LOG_TMP_FILE_PATH

echo "==========tmp dir" >> $LOG_TMP_FILE_PATH
ls -lh /tmp/ >> $LOG_TMP_FILE_PATH
du -sh /tmp/* >> $LOG_TMP_FILE_PATH

echo "==========ifconfig" >> $LOG_TMP_FILE_PATH
ifconfig >> $LOG_TMP_FILE_PATH

echo "==========/proc/net/dev" >> $LOG_TMP_FILE_PATH
cat /proc/net/dev >> $LOG_TMP_FILE_PATH

echo "==========/proc/bus/pci/devices" >> $LOG_TMP_FILE_PATH
cat /proc/bus/pci/devices >> $LOG_TMP_FILE_PATH

echo "==========route" >> $LOG_TMP_FILE_PATH
route -n >> $LOG_TMP_FILE_PATH

echo "==========ip -6 route" >> $LOG_TMP_FILE_PATH
ip -6 route >> $LOG_TMP_FILE_PATH

cat $NETWORK_FILE_PATH | grep -v -e'password' -e'username' > $NETWORK_STRIP

cat $WIRELESS_FILE_PATH | grep -v 'key' > $WIRELESS_STRIP

echo "==========ps" >> $LOG_TMP_FILE_PATH
ps -w >> $LOG_TMP_FILE_PATH

echo "==========nvram" >> $NVRAM_FILE_PATH
nvram show >> $NVRAM_FILE_PATH

echo "==========bdata" >> $BDATA_FILE_PATH
bdata show >> $BDATA_FILE_PATH


log_exec(){
    echo "========== $1" >>$LOG_TMP_FILE_PATH
    eval "$1" >> $LOG_TMP_FILE_PATH
}

flog_exec(){
    echo "========== $1" >>$2
    eval "$1" >> $2
}


list_messages_gz(){
    for file in `ls /data/usr/log/ | grep ^messages\.[1-4]\.gz$`; do
        GZ_LOGS=${GZ_LOGS}" /data/usr/log/"${file}
    done
}

log_exec "cat /proc/meminfo >> $LOG_TMP_MEMINFO"
for i in `seq 0 1`; do
        # wifi
        log_exec "athstats -i wifi$i >> $LOG_TMP_FILE_PATH"
done
list="0 1"
netmode="`uci -q get xiaoqiang.common.NETMODE`"
ifconfig wl14 >/dev/null 2>&1
[ $? = 0 ] && list="$list 14"
[ "$netmode" = "whc_cap" -o "$netmode" = "whc_re" ] && {
        bh_radio_list="`uci get misc.backhauls.backhaul`"
        for bh_radio in $bh_radio_list; do
            bh_vap_if="`uci get misc.backhauls.backhaul_${bh_radio}_ap_iface`"
            bh_sta_if="`uci get misc.backhauls.backhaul_${bh_radio}_sta_iface`"
            if [ -n "$bh_vap_if" ] && [ "$bh_vap_if" != "wl0" ] && [ "$bh_vap_if" != "wl1" ]; then
                bh_vap_if="`echo $bh_vap_if | cut -d l -f 2`"
                bh_vap_list="$bh_vap_list $bh_vap_if"
            fi
            [ -n "$bh_sta_if" ] && {
                bh_sta_if="`echo $bh_sta_if | cut -d l -f 2`"
                bh_sta_list="$bh_sta_list $bh_sta_if"
            }
        done
        list="$list $bh_vap_list"
}
echo "========== list:$list" >> $LOG_TMP_FILE_PATH

# timeout -t 3 cnss_diag -p -c  | grep -e ANI_EDCCA_PHYID -e OFDM_DL
# /usr/sbin/getneighbor.sh ${LOG_TMP_FILE_PATH} > /dev/null 2>&1
for i in $list; do
        # wl
        log_exec "iwinfo wl$i info >> $LOG_TMP_FILE_PATH"
        log_exec "iwinfo wl$i assolist >> $LOG_TMP_FILE_PATH"
        log_exec "iwinfo wl$i txpowerlist >> $LOG_TMP_FILE_PATH"
        log_exec "iwinfo wl$i freqlist >> $LOG_TMP_FILE_PATH"
        log_exec "wlanconfig wl$i list >> $LOG_TMP_FILE_PATH"
        log_exec "iwconfig wl$i >> $LOG_TMP_FILE_PATH"
        log_exec "iwpriv wl$i get_chutil >> $LOG_TMP_FILE_PATH"
        log_exec "iwpriv wl$i get_channf >> $LOG_TMP_FILE_PATH"
    	log_exec "iwpriv wl$i txrx_stats 9"
    	log_exec "iwpriv wl$i txrx_stats 10"
        log_exec "iwpriv wl$i txrx_stats 262" #wds table
        log_exec "hostapd_cli -p /var/run/hostapd-wifi$i -i wl$i get_config | grep -v \"passphrase=\""
done

# /usr/sbin/getneighbor.sh ${LOG_TMP_FILE_PATH} > /dev/null 2>&1
[ "$netmode" = "whc_cap" -o "$netmode" = "whc_re" ] && {
        [ "$netmode" = "whc_re" -a -n "$bh_sta_list" ] && {
            echo "========== bh_sta_list:$bh_sta_list" >> $LOG_TMP_FILE_PATH
            for i in $bh_sta_list; do
                echo "========== @@@@ iwinfo wl$i @@@@" >> $LOG_TMP_FILE_PATH
                echo "========== @@@@ iwinfo wl$i @@@@" > /dev/console
                log_exec "iwinfo wl$i info"
                log_exec "iwconfig wl$i"
                log_exec "wpa_cli -p /var/run/wpa_supplicant-wl$i -i wl$i status"
                log_exec "wpa_cli -p /var/run/wpa_supplicant-wl$i -i wl$i list_networks"
            done
        }

        ### log info for whc serives and state
        flog_exec "  @@@@ whc info log @@@@" "$WHC_LOG"
        flog_exec "#whc general show: " "$WHC_LOG"
	mesh_cmd role >> $WHC_LOG

    flog_exec "#brctl showmacs detail info: " "$WHC_LOG"
    brctl showmacs br-lan >> $WHC_LOG
    flog_exec "#brctl showstp detail info: " "$WHC_LOG"
    brctl showstp br-lan >> $WHC_LOG

    flog_exec "### swconfig info" "$WHC_LOG"
    swconfig dev switch0 show >> $WHC_LOG
}

#The follow print to UART.
echo "==========dmesg:" >> $LOG_TMP_FILE_PATH
dmesg >> $LOG_TMP_FILE_PATH
sleep 1
echo "==========meminfo" >> $LOG_TMP_FILE_PATH
cat $LOG_MEMINFO >> $LOG_TMP_FILE_PATH

echo "==========topinfo" >> $LOG_TMP_FILE_PATH
top -b -n1 >> $LOG_TMP_FILE_PATH

#dump ppp and vpn status
log_exec "cat /tmp/pppoe.log"
log_exec "cat /tmp/vpn.stat.msg"
log_exec "ubus call turbo_ccgame get_pass"


iptables-save -c > $IPTABLES_SAVE

echo "    trafficd hw info:" > $TRAFFICD_LOG
ubus call trafficd hw '{"debug":true}' >> $TRAFFICD_LOG
echo "    trafficd ip info:" >> $TRAFFICD_LOG
ubus call trafficd ip '{"debug":true}' >> $TRAFFICD_LOG
echo "    tbus list:" >> $TRAFFICD_LOG
tbus -v list >> $TRAFFICD_LOG


# list enabled plugin's name
list_plugin /userdisk/appdata/app_infos $PLUGIN_LOG

list_messages_gz

MICLOUD_LOG_PATH="/userdisk/data/.pluginConfig/2882303761517344979/micloudBackup.log"

[ -f $MICLOUD_LOG_PATH ] && {
    FILE_SIZE=`ls -l $MICLOUD_LOG_PATH | awk '{print $5}'`
    [ $FILE_SIZE -lt 4194304 ] && {
        cp $MICLOUD_LOG_PATH $MICLOUD_LOG
    }
}

# busybox's tar requires every source file existing!!
[ -e "$IPTABLES_SAVE" ] || IPTABLES_SAVE=
[ -e "$TRAFFICD_LOG" ] || TRAFFICD_LOG=
[ -e "$PLUGIN_LOG" ] || PLUGIN_LOG=
[ -e "$NETWORK_STRIP" ] || NETWORK_STRIP=
[ -e "$MICLOUD_LOG" ] || MICLOUD_LOG=
[ -e "$NVRAM_FILE_PATH" ] || NVRAM_FILE_PATH=
[ -e "$BDATA_FILE_PATH" ] || BDATA_FILE_PATH=
move_files="$LOG_TMP_MEMINFO $LOG_TMP_FILE_PATH $IPTABLES_SAVE $TRAFFICD_LOG $PLUGIN_LOG $NETWORK_STRIP $WIRELESS_STRIP $MICLOUD_LOG $NVRAM_FILE_PATH $BDATA_FILE_PATH"
[ -e "$DHCP_LEASE" ] || DHCP_LEASE=
[ -e "$DNSMASQ_CONF" ] || DNSMASQ_CONF=
[ -e "$MACFILTER_FILE_PATH" ] || MACFILTER_FILE_PATH=
[ -e "$CRONTAB" ] || CRONTAB=
[ -e "$QOS_CONF" ] || QOS_CONF=
[ -e "$WIFISHARE_CONF" ] || WIFISHARE_CONF=
dup_files="$DHCP_LEASE $DNSMASQ_CONF $MACFILTER_FILE_PATH $CRONTAB $QOS_CONF $WIFISHARE_CONF"

[ -e "$LOGREAD_FILE_PATH" ] || LOGREAD_FILE_PATH=
[ -e "$PANIC_FILE_PATH" ] || PANIC_FILE_PATH=
[ -e "$LOG_WIFI_AYALYSIS" ] || LOG_WIFI_AYALYSIS=
[ -e "$LOG_WIFI_AYALYSIS0" ] || LOG_WIFI_AYALYSIS0=
[ -e "$GZ_LOGS" ] || GZ_LOGS=
[ -e "$LOG_DIR" ] || LOG_DIR=
[ -e "$TMP_WIFI_LOG" ] || TMP_WIFI_LOG=



if [ "$redundancy_mode" = "1" ]; then
    redundancy_files="$LOG_DIR $PANIC_FILE_PATH $LOG_WIFI_AYALYSIS $LOG_WIFI_AYALYSIS0 $GZ_LOGS"
else
    redundancy_files="$LOG_DIR $PANIC_FILE_PATH $TMP_WIFI_LOG"
fi

redundancy_files="$redundancy_files "/tmp/log/" "/tmp/run/""
move_files="$move_files $WHC_LOG"

for ff in hyd-*.conf lbd.conf plc.conf resolv.conf; do
        conf_files="$conf_files `ls /tmp/$ff 2>/dev/null`"
done

dup_files="$dup_files $conf_files"

echo logfile=$LOG_ZIP_FILE_PATH
echo movefile=$move_files
echo dupfile=$dup_files
echo redfile=$redundancy_files

tar -zcf $LOG_ZIP_FILE_PATH $move_files $dup_files $redundancy_files
rm -f $move_files > /dev/null
