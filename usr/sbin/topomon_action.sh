#!/bin/sh

. /lib/functions.sh

TOPOMON_ACTION_FILE_LOCK="/tmp/lock/topomon_action_file.lock"
TOPOMON_STATUS_DIR="/var/run/topomon"

# bit mapping for backhauls represent
BACKHAUL_BMP_2g=0
BACKHAUL_BMP_5g=1
BACKHAUL_BMP_resv=2
BACKHAUL_BMP_eth=3
BACKHAUL_QA_BMP_GOOD=1
BACKHAUL_QA_BMP_POOR=0

RSSI_THRESHOLD_FAR=-72
RSSI_THRESHOLD_NEAR=-60

ROLE_CAP=0
ROLE_RE=1

log(){
	logger -t "topomon action: " -p9 "$1"
}
topomon_action_file_lock()
{
	[ "$1" = "lock" ] && {
		arg="-w"
	} || {
		arg="-u"
	}

	lock "$arg" ${TOPOMON_ACTION_FILE_LOCK}_$2
}

function int2ip()
{
	local hex=$1
	local a=$((hex>>24))
	local b=$((hex>>16&0xff))
	local c=$((hex>>8&0xff))
	local d=$((hex&0xff))

	echo "$a.$b.$c.$d"
}
 
function ip2int()
{
	local ip=$1
	local a=$(echo $ip | awk -F'.' '{print $1}')
	local b=$(echo $ip | awk -F'.' '{print $2}')
	local c=$(echo $ip | awk -F'.' '{print $3}')
	local d=$(echo $ip | awk -F'.' '{print $4}')

	echo "$(((a << 24) + (b << 16) + (c << 8) + d))"
}

__setkv()
{
	matool --method setKV --params "$1" "$2" >/dev/null 2>&1 || {
		log " matool setkv $1 $2 failed!"
	}
}

topomon_update_status() {
	local option="$1"
	local value="$2"

	if [ -n $option -a -d $TOPOMON_STATUS_DIR ]; then
		local status_file="${TOPOMON_STATUS_DIR}/${option}"
		topomon_action_file_lock lock "$option"
		if [ -z $value ]; then
			unlink $status_file
		else
			echo -e $value > $status_file
		fi
		topomon_action_file_lock unlock "$option"
	fi
}

topomon_current_status() {
	local option="$1"
	if [ -n $option ]; then
		local status_file="${TOPOMON_STATUS_DIR}/${option}"
		if [ -f $status_file ]; then
			topomon_action_file_lock lock "$option"
			cat $status_file
			topomon_action_file_lock unlock "$option"
		fi
	fi
}

wpa_supplicant_if_add() {
	local ifname=$1
	local bridge=$2
	local driver="nl80211"

	[ -f "/var/run/wpa_supplicant-$ifname.lock" ] && rm /var/run/wpa_supplicant-$ifname.lock
	wpa_cli -g /var/run/wpa_supplicantglobal interface_add  $ifname /var/run/wpa_supplicant-$ifname.conf $driver /var/run/wpa_supplicant-$ifname "" $bridge
	touch /var/run/wpa_supplicant-$ifname.lock
}

wpa_supplicant_if_remove() {
	local ifname=$1

	[ -f "/var/run/wpa_supplicant-${ifname}.lock" ] && { \
		wpa_cli -g /var/run/wpa_supplicantglobal  interface_remove  ${ifname}
		rm /var/run/wpa_supplicant-${ifname}.lock
	}
}

topomon_wifi_if_down() {
	local sta_iface=$1
	local network_id=
	if [ -n "$sta_iface" ]; then
		network_id=`wpa_cli -p /var/run/wpa_supplicant-$sta_iface list_network | grep CURRENT | awk '{print $1}'`
		if [ -z  $network_id ]; then
			network_id=0
		fi
		log "Interface $sta_iface Brought down with network id $network_id"
		wpa_cli -p /var/run/wpa_supplicant-$sta_iface disable_network $network_id
	fi
}

topomon_wifi_if_up() {
	local sta_iface=$1
	local network_id=
	if [ -n "$sta_iface" ]; then
		ifconfig $sta_iface > /dev/null 2>&1
		if [ $? -eq 0 ]; then
			network_id=`wpa_cli -p /var/run/wpa_supplicant-$sta_iface list_network | grep DISABLED | awk '{print $1}'`
			if [ -z  $network_id ]; then
				network_id=0
			fi
			log "Interface $sta_iface Brought up with network id $network_id"
			wpa_cli -p /var/run/wpa_supplicant-$sta_iface enable_network $network_id
		else
			local wifi_iface=$(uci show wireless | grep ".ifname=\'$sta_iface\'" | awk -F"." '{print $2}')
			uci set wireless.$wifi_iface.disabled=0
			uci commit wireless
			wifi
			wpa_cli -i $sta_iface -p /var/run/wpa_supplicant-$sta_iface enable 0
		fi
	fi
}

set_backhaul_ap_aplimit() {
	local bh_wlan_iface="$1"
	local hop_count="$2"

	[ -z "$bh_wlan_iface" -o -z "$hop_count" ] && return

	if [ $hop_count = "0" ]; then
		cfg80211tool $bh_wlan_iface mesh_aplimit 3
	elif [ $hop_count = "1" ]; then
		cfg80211tool $bh_wlan_iface mesh_aplimit 2
	else
		cfg80211tool $bh_wlan_iface mesh_aplimit 0
		local device_5g=$(uci -q get misc.wireless.if_5G)
		hostapd_cli -i $bh_wlan_iface -p /var/run/hostapd-${device_5g} list_sta | while read line;do sleep 1;cfg80211tool $bh_wlan_iface kickmac $line;done
	fi
}

topomon_set_connect_bssid() {
	local sta_iface=$1
	local restart=$2
	local new_bssid=$(topomon_current_status "best_bssid")

	if [ -n "$sta_iface" -a -n $new_bssid ]; then
		if [ "$restart" -gt 0 ]; then
			# Restart the network with configured BSSID
			log "Bringing down/up $sta_iface due to bssid config & restart!($new_bssid)"
			wpa_cli -p /var/run/wpa_supplicant-$sta_iface disable_network 0
			wpa_cli -p /var/run/wpa_supplicant-$sta_iface set_network 0 bssid $new_bssid
			wpa_cli -p /var/run/wpa_supplicant-$sta_iface enable_network 0
		else
			# Just configure the BSSID
			wpa_cli -p /var/run/wpa_supplicant-$sta_iface set_network 0 bssid $new_bssid
		fi
	fi
}

topomon_re_push() {
	# role
	__setkv "whc_role" "$ROLE_RE"

	# self wanmac
	__setkv "re_whc_wanmac" "`getmac wan`"

	# upnode mac
	local upnode=$(topomon_current_status "uplink_mac")
	[ -n "$upnode" -a "$upnode" != "00:00:00:00:00:00" ] && __setkv "re_whc_upnode" "$upnode"

	# RE backhauls
	local bh_bmp=$(topomon_current_status "backhauls")
	local qa_bmp=$(topomon_current_status "backhauls_qa")
	[ -n "$bh_bmp" ] && {
		__setkv "re_whc_backhauls" "$bh_bmp"
		__setkv "re_whc_backhauls_qa" "$qa_bmp"
	}

	# CAP devid from tbus
	local cap_devid=$(uci -q get bind.info.remoteID)
	[ -n "$cap_devid" ] && __setkv "re_whc_cap_devid" "$cap_devid"

	log " RE push: up $upnode, bh:qa $bh_bmp:$qa_bmp, capdevid $cap_devid"
}

topomon_cap_push() {
	# role
	__setkv "whc_role" "$ROLE_CAP"

	local re_list=""
	[ -e /tmp/xq_whc_quire ] && {
		while read -r LINE
		do
			[ -z "$LINE" ] && continue
			local status=$(parse_json "$LINE" return 2>/dev/null)
			if [ "$status" = "success" ]; then
				local re_devid="`parse_json "$LINE" devid`"
				local re_mac="`parse_json "$LINE" wanmac`"

				local bmp=$(parse_json "$LINE" backhauls)
				[ -z "$bmp" ] && bmp=0
				local locale=$(parse_json "$LINE" locale)
				local initted=$(parse_json "$LINE" initted)
				local ip=$(parse_json "$LINE" ip)

				local re_node="{\"devid\":\"$re_devid\",\"wanmac\":\"$re_mac\",\"backhauls\":\"$bmp\",\"locale\":\"$locale\",\"initted\":\"$initted\",\"ip\":\"$ip\"},"

				log "   re node:$re_node"
				[ "0" = "$initted" ] && {
					log "     re node NOT init-done, ignore push it!"
					continue
				}

				append re_list "$re_node"
			fi

		done < /tmp/xq_whc_quire

		re_list=${re_list%,}
	}
	[ -n "$re_list" ] && __setkv "cap_whc_relist" "[$re_list]" || __setkv "cap_whc_relist" "[]"
}

topomon_link_update() {
	local bh_type="$1"
	local current_qa=$(topomon_current_status "backhauls_qa")
	local now_qa=
	if [ "$bh_type" = "1" ]; then
		#eth backhaul, link quality is always good
		now_qa="$((1<<BACKHAUL_BMP_eth))"
		topomon_update_status "backhauls" "$((1<<BACKHAUL_BMP_eth))"
	elif [ "$bh_type" = "2" ]; then
		local bh_sta_iface=$(uci -q get misc.backhauls.backhaul_5g_sta_iface)
		local rssi=$(iwconfig $bh_sta_iface | grep 'Signal level' | awk -F'=' '{print $3}' | awk '{print $1}')
		topomon_update_status "backhauls" "$((1<<BACKHAUL_BMP_5g))"
		if [ $rssi -ge $RSSI_THRESHOLD_FAR ]; then
			now_qa="$((1<<BACKHAUL_BMP_5g))"
		else
			now_qa="0"
		fi
	fi

	[ "$current_qa" = "$now_qa" ] && return

	topomon_update_status "backhauls_qa" $now_qa
	topomon_re_push
}

topomon_topo_update() {
	local bh_type="$1"
	local port_name="$2"
	local bh_wlan_iface=$(uci -q get misc.backhauls.backhaul_5g_ap_iface)
	local lan_mac=$(ifconfig br-lan | grep HWaddr | awk '{print $5}')
	local int_ip=0
	local uplink_rate=0
	local hop_count=0
	local network_id=$(uci -q get xiaoqiang.common.NETWORK_ID)
	local backhaul_type=
	local uplink_mac=
	local device_5g=$(uci -q get misc.wireless.if_5G)
	local bh_ap_running=$(ifconfig $bh_wlan_iface | grep -wc "RUNNING")
	local bh_sta_iface=$(uci -q get misc.backhauls.backhaul_5g_sta_iface)
	local bh_sta_is_running="1"

	if [ "$bh_type" = "wired" ]; then
		uplink_mac=$3
		int_ip=$4
		uplink_rate=$5
		hop_count=$6
		topomon_update_status "bh_type" $bh_type
		[ $uplink_rate -gt 1000 ] && uplink_rate=1000
		topomon_update_status "eth_link_rate" $uplink_rate
		topomon_update_status "hop_count" $hop_count
		cfg80211tool $bh_wlan_iface mesh_ethmode 1
		cfg80211tool $bh_wlan_iface mesh_capip $int_ip
		cfg80211tool $bh_wlan_iface mesh_ulrate $uplink_rate
		cfg80211tool $bh_wlan_iface mesh_hop $hop_count
		backhaul_type=1
		ubus call xq_info_sync_mqtt topo_changed
	elif [ "$bh_type" = "wireless" ]; then
		cfg80211tool $bh_wlan_iface mesh_ethmode 0
		backhaul_type=2
		topomon_update_status "bh_type" $bh_type
		bh_sta_is_running=$(ifconfig $bh_sta_iface | grep -wc "RUNNING")
		if [ $bh_sta_is_running = "1" ]; then
			int_ip=$(cfg80211tool $bh_wlan_iface g_mesh_capip | awk -F":" '{print $2}')
			uplink_rate=$(cfg80211tool $bh_wlan_iface g_mesh_ulrate | awk -F":" '{print $2}')
			hop_count=$(cfg80211tool $bh_wlan_iface g_mesh_hop | awk -F":" '{print $2}')
			uplink_mac=$(cfg80211tool $bh_wlan_iface g_mesh_ulmac | cut -f2-7 -d":")
			topomon_update_status "eth_link_rate" $uplink_rate
			topomon_update_status "hop_count" $hop_count
			ubus call xq_info_sync_mqtt topo_changed
		else
			#set hop 255 before connected to uplink node
			hop_count=255
			topomon_update_status "hop_count" $hop_count
			wpa_cli -p /var/run/wpa_supplicant-$bh_sta_iface set_network 0 bssid any
		fi
	else
		hop_count=255
		cfg80211tool $bh_wlan_iface mesh_hop $hop_count
		topomon_update_status "hop_count" $hop_count
		uplink_mac=$(topomon_current_status "uplink_mac")
		[ -z $uplink_mac ] && uplink_mac=0
		local curr_bh_type=$(topomon_current_status "bh_type")
		[ "$curr_bh_type" = "wireless" ] && backhaul_type=2 || backhaul_type=1
		local curr_cap_ip=$(topomon_current_status "cap_ip")
		int_ip=$(ip2int $curr_cap_ip)
		wpa_cli -p /var/run/wpa_supplicant-$bh_sta_iface set_network 0 bssid any
	fi

	set_backhaul_ap_aplimit $bh_wlan_iface $hop_count

	if [ $bh_sta_is_running = "1" ]; then
		local str_ip=$(int2ip $int_ip)
		topomon_update_status "uplink_mac" $uplink_mac
		topomon_update_status "cap_ip" $str_ip
		uci -q set xiaoqiang.common.CAP_IP=$str_ip
		uci commit xiaoqiang
		topomon_update_status "port_name" $port_name

		local mac_bin=$(echo $uplink_mac | sed s'/://'g)
		local info=$(printf "%08x%08x%08x%02x%02x%012x" 0x$network_id $uplink_rate $int_ip $hop_count $backhaul_type 0x$mac_bin)
		echo "$lan_mac $info" > /proc/enid/response_info

		if [ "$bh_type" != "isolated" ]; then
			topomon_link_update $backhaul_type
			topomon_re_push
		fi
	fi
}

topomon_check_best_bssid() {
	local sta_iface=$1
	local rssi=$(iwconfig $sta_iface | grep 'Signal level' | awk -F'=' '{print $3}' | awk '{print $1}')

	local best_bssid=$(cfg80211tool $sta_iface g_mesh_bssid | awk -F":" '{print $2}' | sed -e "s/\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)/\1:\2:\3:\4:\5:\6/")

	[ "$best_bssid" = "00:00:00:00:00:00" ] && {
		return 0
	}

	topomon_update_status "best_bssid" $best_bssid
	iwconfig $sta_iface 2>/dev/null | grep -q -i $best_bssid

	if [ $? = 1 ]; then
		log "best bssid is different : $best_bssid"
		return 1
	else
		return 0
	fi
}

topomon_init() {
	local bh_type="$1"
	local port_name="$2"
	local lan_mac=$(ifconfig br-lan | grep HWaddr | awk '{print $5}')
	local bh_wlan_iface=$(uci -q get misc.backhauls.backhaul_5g_ap_iface)
	local int_ip=0
	local uplink_rate=0
	local hop_count=0
	local network_id=$(uci -q get xiaoqiang.common.NETWORK_ID)
	local backhaul_type=
	local uplink_mac=
	local bh_sta_iface=$(uci -q get misc.backhauls.backhaul_5g_sta_iface)

	[ -d $TOPOMON_STATUS_DIR ] || mkdir -p $TOPOMON_STATUS_DIR
	if [ "$bh_type" = "wired" ]; then
		uplink_mac=$3
		int_ip=$4
		uplink_rate=$5
		hop_count=$6
		[ $uplink_rate -gt 1000 ] && uplink_rate=1000

		cfg80211tool $bh_wlan_iface mesh_ethmode 1
		cfg80211tool $bh_wlan_iface mesh_capip $int_ip
		cfg80211tool $bh_wlan_iface mesh_ulrate $uplink_rate
		cfg80211tool $bh_wlan_iface mesh_hop $hop_count
		backhaul_type=1
	else
		local wifi_iface=$(uci show wireless | grep ".ifname=\'$bh_sta_iface\'" | awk -F"." '{print $2}')
		local sta_disabled=$(uci -q get wireless.$wifi_iface.disabled)
		cfg80211tool $bh_wlan_iface mesh_ethmode 0
		backhaul_type=2
		if [ $sta_disabled = "1" ]; then
			uci set wireless.$wifi_iface.disabled=0
			uci commit wireless
			wifi
		fi
		wpa_cli -i $bh_sta_iface -p /var/run/wpa_supplicant-$bh_sta_iface enable 0
		sleep 2
		local bh_sta_is_running=$(ifconfig $bh_sta_iface | grep -wc "RUNNING")
		if [ $bh_sta_is_running = "1" ]; then
			int_ip=$(cfg80211tool $bh_wlan_iface g_mesh_capip | awk -F":" '{print $2}')
			uplink_rate=$(cfg80211tool $bh_wlan_iface g_mesh_ulrate | awk -F":" '{print $2}')
			hop_count=$(cfg80211tool $bh_wlan_iface g_mesh_hop | awk -F":" '{print $2}')
			uplink_mac=$(cfg80211tool $bh_wlan_iface g_mesh_ulmac | cut -f2-7 -d":")
		else
			local str_ip=$(uci -q get xiaoqiang.common.CAP_IP)
			[ -n "$str_ip" ] && int_ip=$(ip2int $str_ip)
			uplink_rate=0
			hop_count=255
			uplink_mac=0
		fi
	fi

	if [ $int_ip != "0" ]; then
		local str_ip=$(int2ip $int_ip)
		[ "$str_ip" != "0.0.0.0" ] && {
			topomon_update_status "cap_ip" $str_ip
			uci -q set xiaoqiang.common.CAP_IP=$str_ip
			uci commit xiaoqiang
		}
	fi

	topomon_update_status "uplink_mac" $uplink_mac
	topomon_update_status "bh_type" $bh_type
	topomon_update_status "hop_count" $hop_count
	topomon_update_status "eth_link_rate" $uplink_rate
	[ $port_name != "null" ] && topomon_update_status "port_name" $port_name
	topomon_link_update $backhaul_type

	set_backhaul_ap_aplimit $bh_wlan_iface $hop_count

	local mac_bin=$(echo $uplink_mac | sed s'/://'g)
	local info=$(printf "%08x%08x%08x%02x%02x%012x" 0x$network_id $uplink_rate $int_ip $hop_count $backhaul_type 0x$mac_bin)
	echo "$lan_mac $info" > /proc/enid/response_info

	if [ "$bh_type" = "wired" ]; then
		topomon_wifi_if_down $bh_sta_iface
	fi

	[ $hop_count != "255" ] && topomon_re_push
}

topomon_update_cap_wifi_param() {
	local bh_wlan_iface=$(uci -q get misc.backhauls.backhaul_5g_ap_iface)
	local wait=$1

	[ -z "$wait" ] && wait=1

	if [ $wait -eq 1 ]; then
		for i in {1..15}
		do
			ifconfig $bh_wlan_iface > /dev/null 2>&1
			if [ $? -eq 0 ]; then
				break
			else
				sleep 2
			fi
		done
	fi

	local lan_mac=$(ifconfig br-lan | grep HWaddr | awk '{print $5}')
	local str_ip=$(ifconfig br-lan | grep "inet\ addr" | awk '{print $2}' | awk -F: '{print $2}')
	local int_ip=$(ip2int $str_ip)
	local uplink_rate=9999
	local hop_count=0
	local network_id=$(uci -q get xiaoqiang.common.NETWORK_ID)
	local backhaul_type=0

	local device=$(uci -q get misc.wireless.if_5G)

	cfg80211tool $bh_wlan_iface mesh_capip $int_ip
	cfg80211tool $bh_wlan_iface mesh_hop 0

	local info=$(printf "%08x%08x%08x%02x%02x%012x" 0x$network_id $uplink_rate $int_ip $hop_count $backhaul_type 0x0)
	echo "$lan_mac $info" > /proc/enid/response_info

	echo "update cap mesh param done" >> /dev/console
	topomon_cap_push
}

topomon_ping_test() {
	local ip=$1
	ping $1 -c 1 -w 2 > /dev/null 2>&1
	if [ $? -eq 0 ]; then
		echo "success"
	else
		echo "failed"
	fi
}

topomon_enid_init() {
	local lan_mac=$(ifconfig br-lan | grep HWaddr | awk '{print $5}')
	echo "$lan_mac 0000000000000000000000000000000000000000" > /proc/enid/response_info
	echo "re enid init done" >> /dev/console
}

topomon_enid_update() {
	local uplink_mac=$1
	local int_ip=$2
	local uplink_rate=$3
	local hop_count=$4
	local port_name=$5
	local lan_mac=$(ifconfig br-lan | grep HWaddr | awk '{print $5}')
	local backhaul_type=1
	local str_ip=$(int2ip $int_ip)
	local network_id=$(uci -q get xiaoqiang.common.NETWORK_ID)
	local bh_wlan_iface=$(uci -q get misc.backhauls.backhaul_5g_ap_iface)
	local current_ip=$(topomon_current_status "cap_ip")
	local bh_ap_running=$(ifconfig $bh_wlan_iface | grep -wc "RUNNING")

	[ "$str_ip" = "$current_ip" ] || {
		topomon_update_status "cap_ip" $str_ip
		uci -q set xiaoqiang.common.CAP_IP=$str_ip
		uci commit xiaoqiang
	}

	[ $uplink_rate -gt 1000 ] && uplink_rate=1000
	topomon_update_status "bh_type" "wired"
	topomon_update_status "uplink_mac" $uplink_mac
	topomon_update_status "eth_link_rate" $uplink_rate
	topomon_update_status "hop_count" $hop_count
	topomon_update_status "port_name" $port_name

	cfg80211tool $bh_wlan_iface mesh_capip $int_ip
	cfg80211tool $bh_wlan_iface mesh_ulrate $uplink_rate
	cfg80211tool $bh_wlan_iface mesh_hop $hop_count

	set_backhaul_ap_aplimit $bh_wlan_iface $hop_count

	local mac_bin=$(echo $uplink_mac | sed s'/://'g)
	local info=$(printf "%08x%08x%08x%02x%02x%012x" 0x$network_id $uplink_rate $int_ip $hop_count $backhaul_type 0x$mac_bin)
	echo "$lan_mac $info" > /proc/enid/response_info
}

topomon_wireless_update() {
	local status_changed=0
	local bh_wlan_iface=$(uci -q get misc.backhauls.backhaul_5g_ap_iface)
	local int_ip=$(cfg80211tool $bh_wlan_iface g_mesh_capip | awk -F":" '{print $2}')
	local str_ip=$(int2ip $int_ip)
	local current_ip=$(topomon_current_status "cap_ip")
	local hop_changed=0
	[ "$str_ip" = "$current_ip" ] || {
		status_changed=1
		topomon_update_status "cap_ip" $str_ip
		uci -q set xiaoqiang.common.CAP_IP=$str_ip
		uci commit xiaoqiang
	}

	local uplink_rate=$(cfg80211tool $bh_wlan_iface g_mesh_ulrate | awk -F":" '{print $2}')
	local current_uprate=$(topomon_current_status "eth_link_rate")
	[ "$uplink_rate" = "$current_uprate" ] || {
		status_changed=1
		topomon_update_status "eth_link_rate" $uplink_rate
	}

	local hop_count=$(cfg80211tool $bh_wlan_iface g_mesh_hop | awk -F":" '{print $2}')
	local current_hop=$(topomon_current_status "hop_count")
	[ "$hop_count" = "$current_hop" ] || {
		status_changed=1
		hop_changed=1
		topomon_update_status "hop_count" $hop_count
		set_backhaul_ap_aplimit $bh_wlan_iface $hop_count
	}

	[ $status_changed -eq 1 ] && {
		local network_id=$(uci -q get xiaoqiang.common.NETWORK_ID)
		local backhaul_type=2
		local lan_mac=$(ifconfig br-lan | grep HWaddr | awk '{print $5}')
		local uplink_mac=$(cfg80211tool $bh_wlan_iface g_mesh_ulmac | cut -f2-7 -d":")
		local mac_bin=$(echo $uplink_mac | sed s'/://'g)
		local info=$(printf "%08x%08x%08x%02x%02x%012x" 0x$network_id $uplink_rate $int_ip $hop_count $backhaul_type 0x$mac_bin)
		echo "$lan_mac $info" > /proc/enid/response_info
		[ $hop_changed -eq 1 ] && ubus call xq_info_sync_mqtt topo_changed
	}
}

topomon_push() {
	local role="$1"
	if [ "$role" = "RE" -o "$role" = "re" ]; then
		topomon_re_push
	elif [ "$role" = "CAP" -o "$role" = "cap" ]; then
		topomon_cap_push
	else
		log "Push error : unknown role $role"
	fi
}

topomon_cac_status_check() {
	local ifname=$1
	local status=$(cfg80211tool $ifname get_cac_stat | grep -w $ifname | awk -F: '{print $2}')
	if [ -n $status -a $status = "0" ]; then
		return 0
	else
		return 1
	fi
}

topomon_update_re_wifi_param() {
	local backhaul_5g_ap_iface=$(uci -q get misc.backhauls.backhaul_5g_ap_iface)
	local bh_type=$(topomon_current_status "bh_type")

	[ -z $bh_type ] && return

	if [ "$bh_type" = "wired" ]; then
		cfg80211tool $backhaul_5g_ap_iface mesh_ethmode 1
		local str_ip=$(topomon_current_status "cap_ip")
		local hop_count=$(topomon_current_status "hop_count")
		local ulrate=$(topomon_current_status "eth_link_rate")
		[ -n $str_ip ] && {
			local bin_ip=$(ip2int $str_ip)
			cfg80211tool $backhaul_5g_ap_iface mesh_capip $bin_ip
		}
		[ -n $hop_count ] && cfg80211tool $backhaul_5g_ap_iface mesh_hop $hop_count
		[ -n $ulrate ] && cfg80211tool $backhaul_5g_ap_iface mesh_ulrate $ulrate
	else
		cfg80211tool $backhaul_5g_ap_iface mesh_ethmode 0
	fi
	echo "update re mesh param done" >> /dev/console
}

topomon_update_mesh_param() {
	local netmod=$(uci -q get xiaoqiang.common.NETMODE)
	local capmod=$(uci -q get xiaoqiang.common.CAP_MODE)
	if [ "whc_cap" = "$netmod" -o "lanapmode" = "$netmod" -a "ap" = "$capmod" ]; then
		topomon_update_cap_wifi_param 0
	elif [ "whc_re" = "$netmod" ]; then
		topomon_update_re_wifi_param
	fi
}

#trigger to get new DHCP-IP dynamically
#generally called when ping failed.
trigger_dhcp_new_ip(){
	iface="br-lan"
	pid_file="/var/run/udhcpc-${iface}.pid"
	if [ -f "$pid_file" ]; then
		#trigger udhcpc to renew/rebound DHCP-IP
		cat $pid_file |xargs kill -SIGUSR1
	else
		log "WARN: udhcpc pid file not exist, udhcpc not running?!"
	fi
}

case "$1" in
	init)
	topomon_init "$2" "$3" "$4" "$5" "$6" "$7"
	;;
	ping_test)
	topomon_ping_test "$2"
	;;
	wifi_if_up)
	topomon_wifi_if_up "$2"
	;;
	wifi_if_down)
	topomon_wifi_if_down "$2"
	;;
	set_connect_bssid)
	topomon_set_connect_bssid "$2" "$3"
	;;
	check_best_bssid)
	topomon_check_best_bssid "$2"
	;;
	topo_update)
	topomon_topo_update "$2" "$3" "$4" "$5" "$6" "$7"
	;;
	update_status)
	topomon_update_status "$2" "$3"
	;;
	current_status)
	topomon_current_status "$2"
	;;
	cap_init)
	topomon_update_cap_wifi_param "$2"
	;;
	enid_init)
	topomon_enid_init
	;;
	enid_update)
	topomon_enid_update "$2" "$3" "$4" "$5" "$6"
	;;
	link_update)
	topomon_link_update "$2"
	;;
	wireless_update)
	topomon_wireless_update
	;;
	push)
	topomon_push "$2"
	;;
	cac_status_check)
	topomon_cac_status_check "$2"
	;;
	update_mesh_param)
	topomon_update_mesh_param
	;;
	trigger_dhcp_new_ip)
	trigger_dhcp_new_ip
	;;
	*)
	;;
esac