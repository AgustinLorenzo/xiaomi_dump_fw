#!/bin/sh
# Copyright (C) 2020 Xiaomi

. /lib/mimesh/mimesh_public.sh
. /lib/mimesh/mimesh_stat.sh
. /lib/mimesh/mimesh_init.sh

log(){
	logger -t "meshd connect: " -p9 "$1"
}
check_re_initted(){
	initted=`uci -q get xiaoqiang.common.INITTED`
	[ "$initted" == "YES" ] && { log "RE already initted. exit 0." ; exit 0; }
}
run_with_lock(){
	{
		log "$$, ====== TRY locking......"
		flock -x -w 60 1000
		[ $? -eq "1" ] && { log "$$, ===== GET lock failed. exit 1" ; exit 1 ; }
		log "$$, ====== GET lock to RUN."
		$@
		log "$$, ====== END lock to RUN."
	} 1000<>/var/log/mesh_connect_lock.lock
}
usage() {
	echo "$0 re_start xx:xx:xx:xx:xx:xx"
	echo "$0 help"
	exit 1
}

eth_down() {
	local ifnames=$(uci -q get network.lan.ifname)
	local wan_ifname=$(uci -q get network.wan.ifname)
	for if_name in $ifnames
	do
		ifconfig $if_name down
	done
	ifconfig $wan_ifname down
}

eth_up() {
	local ifnames=$(uci -q get network.lan.ifname)
	local wan_ifname=$(uci -q get network.wan.ifname)
	for if_name in $ifnames
	do
		ifconfig $if_name up
	done
	ifconfig $wan_ifname up
}

set_network_id() {
	local bh_ssid=$1
	local pre_id=$(uci -q get xiaoqiang.common.NETWORK_ID)
	local new_id=$(echo "$bh_ssid" | md5sum | cut -c 1-8)
	if [ -z "$pre_id" -o "$pre_id" != "$new_id" ]; then
		uci set xiaoqiang.common.NETWORK_ID="$new_id"
		uci commit xiaoqiang
	fi
}

cap_close_wps() {
	local ifname=$(uci -q get misc.wireless.ifname_5G)
	local device=$(uci -q get misc.wireless.if_5G)
	hostapd_cli -i $ifname -p /var/run/hostapd-${device} -P /var/run/hostapd_cli-${ifname}.pid wps_cancel
	iwpriv $ifname miwifi_mesh 3
	hostapd_cli -i $ifname -p /var/run/hostapd-${device} -P /var/run/hostapd_cli-${ifname}.pid update_beacon
}

cap_disable_wps_trigger() {
	local ifname=$2
	local device=$1

	#uci set wireless.@wifi-iface[1].miwifi_mesh=3
	#uci commit wireless

	iwpriv $ifname miwifi_mesh 3
	hostapd_cli -i $ifname -p /var/run/hostapd-${device} -P /var/run/hostapd_cli-${ifname}.pid update_beacon
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

re_clean_vap() {
	local ifname=$(uci -q get misc.wireless.apclient_5G)

	wpa_supplicant_if_remove $ifname
	wlanconfig $ifname destroy -cfg80211

	local lanip=$(uci -q get network.lan.ipaddr)
	if [ "$lanip" != "" ]; then
		ifconfig br-lan $lanip
	else
		ifconfig br-lan 192.168.31.1
	fi

	eth_up
	wifi
}

check_re_init_status_v2() {
	for i in $(seq 1 60)
	do
		mimesh_re_assoc_check > /dev/null 2>&1
		[ $? = 0 ] && break
		sleep 2
	done

	mimesh_init_done "re"
	/etc/init.d/meshd stop
	eth_up
}

do_re_init() {
	local ifname=$(uci -q get misc.wireless.apclient_5G)
	local device=$(uci -q get misc.wireless.if_5G)
	#local ifname_2g=$(uci -q get misc.wireless.ifname_2G)

	#local ssid_2g=$(printf "%s" $1 | base64 -d)
	local ssid_2g="$1"
	local pswd_2g=
	local mgmt_2g=$3
	#[ "$mgmt_2g" = "none" ] || pswd_2g=$(printf "%s" $2 | base64 -d)
	[ "$mgmt_2g" = "none" ] || pswd_2g="$2"
	#local ssid_5g=$(printf "%s" $4 | base64 -d)
	local ssid_5g="$4"
	local pswd_5g=
	local mgmt_5g=$6
	#[ "$mgmt_5g" = "none" ] || pswd_5g=$(printf "%s" $5 | base64 -d)
	[ "$mgmt_5g" = "none" ] || pswd_5g="$5"
	local bh_ssid=$(printf "%s" $7 | base64 -d)
	local bh_pswd=$(printf "%s" $8 | base64 -d)
	local bh_mgmt=$9

	#local ssid=$(grep "ssid=\"" /var/run/wpa_supplicant-${ifname}.conf | awk -F\" '{print $2}')
	#local key=$(grep "psk=\"" /var/run/wpa_supplicant-${ifname}.conf | awk -F\" '{print $2}')

	set_network_id "$bh_ssid"

	wpa_supplicant_if_remove $ifname
	wlanconfig $ifname destroy -cfg80211

	touch /tmp/bh_maclist_5g
	#touch /tmp/bh_maclist_2g
	local bh_maclist_5g=$(cat /tmp/bh_maclist_5g | sed 's/ /,/g')
	#local bh_maclist_2g=$(cat /tmp/bh_maclist_2g | sed 's/ /,/g')
	local bh_macnum_5g=$(echo $bh_maclist_5g | awk -F"," '{print NF}')
	#local bh_macnum_2g=$(echo $bh_maclist_2g | awk -F"," '{print NF}')

	do_re_init_json

	local buff="{\"method\":\"init\",\"params\":{\"whc_role\":\"RE\",\"bsd\":\"0\",\"ssid_2g\":\"${ssid_2g}\",\"pswd_2g\":\"${pswd_2g}\",\"mgmt_2g\":\"${mgmt_2g}\",\"ssid_5g\":\"${ssid_5g}\",\"pswd_5g\":\"${pswd_5g}\",\"mgmt_5g\":\"${mgmt_5g}\",\"bh_ssid\":\"${bh_ssid}\",\"bh_pswd\":\"${bh_pswd}\",\"bh_mgmt\":\"${bh_mgmt}\",\"bh_macnum_5g\":\"${bh_macnum_5g}\",\"bh_maclist_5g\":\"${bh_maclist_5g}\",\"bh_macnum_2g\":\"0\",\"bh_maclist_2g\":\"\"}}"

		mimesh_init "$buff" "$10"
		sleep 2
		check_re_init_status_v2
}

do_re_init_bsd() {
	local ifname=$(uci -q get misc.wireless.apclient_5G)
	local device=$(uci -q get misc.wireless.if_5G)
	#local ifname_2g=$(uci -q get misc.wireless.ifname_2G)

	#local whc_ssid=$(printf "%s" $1 | base64 -d)
	local whc_ssid="$1"
	local whc_pswd=
	local whc_mgmt=$3
	#[ "$whc_mgmt" = "none" ] || whc_pswd=$(printf "%s" $2 | base64 -d)
	[ "$whc_mgmt" = "none" ] || whc_pswd="$2"
	local bh_ssid=$(printf "%s" $4 | base64 -d)
	local bh_pswd=$(printf "%s" $5 | base64 -d)
	local bh_mgmt=$6

	#local ssid=$(grep "ssid=\"" /var/run/wpa_supplicant-${ifname}.conf | awk -F\" '{print $2}')
	#local key=$(grep "psk=\"" /var/run/wpa_supplicant-${ifname}.conf | awk -F\" '{print $2}')

	set_network_id "$bh_ssid"

	wpa_supplicant_if_remove $ifname
	wlanconfig $ifname destroy -cfg80211

	touch /tmp/bh_maclist_5g
	#touch /tmp/bh_maclist_2g
	local bh_maclist_5g=$(cat /tmp/bh_maclist_5g | sed 's/ /,/g')
	#local bh_maclist_2g=$(cat /tmp/bh_maclist_2g | sed 's/ /,/g')
	local bh_macnum_5g=$(echo $bh_maclist_5g | awk -F"," '{print NF}')
	#local bh_macnum_2g=$(echo $bh_maclist_2g | awk -F"," '{print NF}')

	do_re_init_json

	local buff="{\"method\":\"init\",\"params\":{\"whc_role\":\"RE\",\"whc_ssid\":\"${whc_ssid}\",\"whc_pswd\":\"${whc_pswd}\",\"whc_mgmt\":\"${whc_mgmt}\",\"bh_ssid\":\"${bh_ssid}\",\"bh_pswd\":\"${bh_pswd}\",\"bh_mgmt\":\"${bh_mgmt}\",\"bh_macnum_5g\":\"${bh_macnum_5g}\",\"bh_maclist_5g\":\"${bh_maclist_5g}\",\"bh_macnum_2g\":\"0\",\"bh_maclist_2g\":\"\"}}"

		mimesh_init "$buff" "$7"
		sleep 2
		check_re_init_status_v2
}

do_re_init_json() {
	local jsonbuf=$(cat /tmp/extra_wifi_param 2>/dev/null)
	[ -z "$jsonbuf" ] && return

	#set max mesh version we can support
	local version_list=$(uci -q get misc.mesh.version)
	if [ -z "$version_list" ]; then
		log "version list is empty"
		return
	fi

	local max_version=1
	for version in $version_list; do
		if [ $version -gt $max_version ]; then
			max_version=$version
		fi
	done

	uci set xiaoqiang.common.MESH_VERSION="$max_version"
		uci commit

	local device_2g=$(uci -q get misc.wireless.if_2G)
	local device_5g=$(uci -q get misc.wireless.if_5G)
	local ifname_2g=$(uci -q get misc.wireless.ifname_2G)
	local ifname_5g=$(uci -q get misc.wireless.ifname_5G)

	local hidden_2g=$(json_get_value "$jsonbuf" "hidden_2g")
	local hidden_5g=$(json_get_value "$jsonbuf" "hidden_5g")
	local disabled_2g=$(json_get_value "$jsonbuf" "disabled_2g")
	local disabled_5g=$(json_get_value "$jsonbuf" "disabled_5g")
	local ax_2g=$(json_get_value "$jsonbuf" "ax_2g")
	local ax_5g=$(json_get_value "$jsonbuf" "ax_5g")
	local txpwr_2g=$(json_get_value "$jsonbuf" "txpwr_2g")
	local txpwr_5g=$(json_get_value "$jsonbuf" "txpwr_5g")
	local bw_2g=$(json_get_value "$jsonbuf" "bw_2g")
	local bw_5g=$(json_get_value "$jsonbuf" "bw_5g")
	local txbf_2g=$(json_get_value "$jsonbuf" "txbf_2g")
	local txbf_5g=$(json_get_value "$jsonbuf" "txbf_5g")
	local ch_2g=$(json_get_value "$jsonbuf" "ch_2g")
	local ch_5g=$(json_get_value "$jsonbuf" "ch_5g")
	local web_passwd=$(json_get_value "$jsonbuf" "web_passwd")

	local support160=$(json_get_value "$jsonbuf" "support160")

	[ "$ch_5g" != "auto" -a "$ch_5g" -gt 48 ] && ch_5g="auto"
	uci set wireless.$device_5g.channel="$ch_5g"
	uci set wireless.$device_2g.channel="$ch_2g"

	uci set wireless.$device_5g.ax="$ax_5g"
	uci set wireless.$device_2g.ax="$ax_2g"

	uci set wireless.$device_5g.txpwr="$txpwr_5g"
	uci set wireless.$device_2g.txpwr="$txpwr_2g"

	uci set wireless.$device_5g.txbf="$txbf_5g"
	uci set wireless.$device_2g.txbf="$txbf_2g"

	uci set wireless.$device_2g.bw="$bw_2g"
	if [ "$support160" = "1" ]; then
		uci set wireless.$device_5g.bw="$bw_5g"
	else
		if [ "$bw_5g" = "0" ]; then
			uci set wireless.$device_5g.bw='80'
		else
			uci set wireless.$device_5g.bw="$bw_5g"
		fi
	fi

	local iface_2g=$(uci show wireless | grep -w "ifname=\'$ifname_2g\'" | awk -F"." '{print $2}')
	local iface_5g=$(uci show wireless | grep -w "ifname=\'$ifname_5g\'" | awk -F"." '{print $2}')

	uci set wireless.$iface_2g.hidden="$hidden_2g"
	uci set wireless.$iface_5g.hidden="$hidden_5g"
	
	uci set wireless.$iface_2g.disabled="0"
	uci set wireless.$iface_5g.disabled="0"

	if [ -n "$web_passwd" ]; then
		uci set account.common.admin="$web_passwd"
		uci commit account
	fi

	uci commit wireless

	#cap_mode
	local cap_mode=$(json_get_value "$jsonbuf" "cap_mode")
	uci set xiaoqiang.common.CAP_MODE="$cap_mode"

	local cap_ip=$(json_get_value "$jsonbuf" "cap_ip")
	[ -n "$cap_ip" ] && uci -q set xiaoqiang.common.CAP_IP="$cap_ip"

	if [ "$cap_mode" = "ap" ]; then
		local vendorinfo=$(json_get_value "$jsonbuf" "vendorinfo")
		uci set xiaoqiang.common.vendorinfo="$vendorinfo"
	fi
	uci commit xiaoqiang
}

init_cap_mode() {
	local ifname_5g=$(uci -q get misc.wireless.ifname_5G)
	local iface_5g=$(uci show wireless | grep -w "ifname=\'$ifname_5g\'" | awk -F"." '{print $2}')
	/etc/init.d/meshd stop
	uci set wireless.$iface_5g.miwifi_mesh=0
	uci commit wireless
}

cap_delete_vap() {
	local ifname=$(uci -q get misc.wireless.mesh_ifname_5G)

	local hostapd_pid=$(ps | grep "hostapd\ /var/run/hostapd-${ifname}.conf" | awk '{print $1}')

	[ -z "$hostapd_pid" ] || kill -9 $hostapd_pid

	rm -f /var/run/hostapd-${ifname}.conf
	wlanconfig $ifname destroy -cfg80211
}

cap_clean_vap() {
	local ifname=$1
	local name=$(echo $2 | sed s/[:]//g)
	cap_delete_vap
	echo "failed" > /tmp/${name}-status
}

check_cap_init_status_v2() {
	local ifname=$(uci -q get misc.backhauls.backhaul_5g_ap_iface)
	local device_5g=$(uci -q get misc.wireless.if_5G)
	local re_5g_mac=$2
	local is_cable=$5
	[ -z "$is_cable" ] && is_cable=0

	for i in $(seq 1 60)
	do
		mimesh_cap_bh_check > /dev/null 2>&1
		if [ $? = 0 ]; then
			mimesh_init_done "cap"
			sleep 2
			init_done=1
			break
		fi
		sleep 2
	done


	if [ $init_done -eq 1 ]; then
		for i in $(seq 1 90)
		do
			local assoc_count1=$(iwinfo $ifname a | grep -i -c $3)
			local assoc_count2=$(iwinfo $ifname a | grep -i -c $4)
			local assoc_count3=0
			if [ $(expr $i % 5) -eq 0 ]; then
				assoc_count3=$(ubus call trafficd hw | grep -iwc $re_5g_mac)
			fi
			if [ $is_cable == "1" -o $assoc_count1 -gt 0 -o $assoc_count2 -gt 0 -o $assoc_count3 -gt 0 ]; then
				/sbin/cap_push_backhaul_whitelist.sh
				/usr/sbin/topomon_action.sh cap_init
				echo "success" > /tmp/$1-status
				radartool -i $device_5g enable
				exit 0
			fi
			sleep 2
		done
	fi

	echo "failed" > /tmp/$1-status
	radartool -i $device_5g enable
	exit 1
}

do_cap_init_bsd() {
	local name=$(echo $1 | sed s/[:]//g)
	local is_cable=$8
	[ -z "$is_cable" ] && is_cable=0

	local ifname_ap_2g=$(uci -q get misc.wireless.ifname_2G)
	local iface_2g=$(uci show wireless | grep -w "ifname=\'$ifname_ap_2g\'" | awk -F"." '{print $2}')

	local whc_ssid=$(uci -q get wireless.$iface_2g.ssid)
	local whc_pswd=$(uci -q get wireless.$iface_2g.key)
	local whc_mgmt=$(uci -q get wireless.$iface_2g.encryption)

	local ifname_5g=$(uci -q get misc.backhauls.backhaul_5g_ap_iface)

	local bh_ssid=$(printf "%s" $6 | base64 -d)
	local bh_pswd=$(printf "%s" $7 | base64 -d)
	local init_done=0

	local device_5g=$(uci -q get misc.wireless.if_5G)

	local channel=$(uci -q get wireless.$device_5g.channel)
	local bw=$(uci -q get wireless.$device_5g.bw)

	local bh_maclist_5g=

	echo "syncd" > /tmp/${name}-status

	set_network_id "$bh_ssid"

	cap_delete_vap

	local mode=$(uci -q get xiaoqiang.common.NETMODE)
	local bh_ap_iface_5g=$(uci show wireless | grep -w "ifname=\'$ifname_5g\'" | awk -F"." '{print $2}')

	local maclist_5g=
	[ -z $bh_ap_iface_5g ] || maclist_5g=$(uci -q get wireless.$bh_ap_iface_5g.maclist | sed 's/ /,/g')
	local exist_5g=$(echo $maclist_5g | grep -i -c $3)

	local cap_mode=$(uci -q get xiaoqiang.common.CAP_MODE)
	if [ "whc_cap" = "$mode" -o "$mode" = "lanapmode" -a "$cap_mode" = "ap" ]; then
		[ "$exist_5g" -eq 0 ] && {
			cfg80211tool $ifname_5g addmac_sec $3
			cfg80211tool $ifname_5g addmac_sec $5
			cfg80211tool $ifname_5g maccmd_sec 1

			uci -q add_list wireless.$bh_ap_iface_5g.maclist=$3
			uci -q add_list wireless.$bh_ap_iface_5g.maclist=$5

			uci commit wireless
		}
	else
		if [ "$maclist_5g" = "" ]; then
			bh_maclist_5g="$3,$5"
		else
			[ "$exist_5g" -eq 0 ] && bh_maclist_5g="$maclist_5g,$3,$5"
		fi

		local bh_macnum_5g=$(echo $bh_maclist_5g | awk -F"," '{print NF}')

		if [ "$whc_mgmt" == "ccmp" ]; then
			whc_pswd=$(uci -q get wireless.$iface_2g.sae_password)
		fi

		whc_ssid=$(printf "%s" $whc_ssid | base64 | xargs)
		whc_pswd=$(printf "%s" $whc_pswd | base64 | xargs)

		case "$channel" in
			52|56|60|64|100|104|108|112|116|120|124|128|132|136|140|149|153|157|161|165)
				uci set wireless.$device_5g.channel='auto'
				uci commit wireless
				;;
			*) ;;
		esac

		#ignore CAC on first init
		radartool -i $device_5g disable

		local buff="{\"method\":\"init\",\"params\":{\"whc_role\":\"CAP\",\"whc_ssid\":\"${whc_ssid}\",\"whc_pswd\":\"${whc_pswd}\",\"whc_mgmt\":\"${whc_mgmt}\",\"bh_ssid\":\"${bh_ssid}\",\"bh_pswd\":\"${bh_pswd}\",\"bh_mgmt\":\"psk2\",\"bh_macnum_5g\":\"${bh_macnum_5g}\",\"bh_maclist_5g\":\"${bh_maclist_5g}\",\"bh_macnum_2g\":\"0\",\"bh_maclist_2g\":\"\"}}"

			mimesh_init "$buff"
	fi

		check_cap_init_status_v2 $name $1 $3 $5 $is_cable
}

do_cap_init() {
	local name=$(echo $1 | sed s/[:]//g)
	local is_cable=$8
	[ -z "$is_cable" ] && is_cable=0

	local ifname_ap_2g=$(uci -q get misc.wireless.ifname_2G)
	local iface_2g=$(uci show wireless | grep -w "ifname=\'$ifname_ap_2g\'" | awk -F"." '{print $2}')
	local ifname_ap_5g=$(uci -q get misc.wireless.ifname_5G)
	local iface_5g=$(uci show wireless | grep -w "ifname=\'$ifname_ap_5g\'" | awk -F"." '{print $2}')
	local device_5g=$(uci -q get misc.wireless.if_5G)

	local ssid_2g=$(uci -q get wireless.$iface_2g.ssid)
	local pswd_2g=$(uci -q get wireless.$iface_2g.key)
	local mgmt_2g=$(uci -q get wireless.$iface_2g.encryption)
	local ssid_5g=$(uci -q get wireless.$iface_5g.ssid)
	local pswd_5g=$(uci -q get wireless.$iface_5g.key)
	local mgmt_5g=$(uci -q get wireless.$iface_5g.encryption)

	local ifname_5g=$(uci -q get misc.backhauls.backhaul_5g_ap_iface)

	local bh_ssid=$(printf "%s" $6 | base64 -d)
	local bh_pswd=$(printf "%s" $7 | base64 -d)
	local init_done=0

	local channel=$(uci -q get wireless.$device_5g.channel)
	local bw=$(uci -q get wireless.$device_5g.bw)

	local bh_maclist_5g=

	echo "syncd" > /tmp/${name}-status

	set_network_id "$bh_ssid"

	cap_delete_vap

	local mode=$(uci -q get xiaoqiang.common.NETMODE)
	local bh_ap_iface_5g=$(uci show wireless | grep -w "ifname=\'$ifname_5g\'" | awk -F"." '{print $2}')

	local maclist_5g=
	[ -z $bh_ap_iface_5g ] || maclist_5g=$(uci -q get wireless.$bh_ap_iface_5g.maclist | sed 's/ /,/g')
	local exist_5g=$(echo $maclist_5g | grep -i -c $3)

	local cap_mode=$(uci -q get xiaoqiang.common.CAP_MODE)
	if [ "whc_cap" = "$mode" -o "$mode" = "lanapmode" -a "$cap_mode" = "ap" ]; then
		[ "$exist_5g" -eq 0 ] && {
			cfg80211tool $ifname_5g addmac_sec $3
			cfg80211tool $ifname_5g addmac_sec $5
			cfg80211tool $ifname_5g maccmd_sec 1

			uci -q add_list wireless.$bh_ap_iface_5g.maclist=$3
			uci -q add_list wireless.$bh_ap_iface_5g.maclist=$5
			uci commit wireless
		}
	else
		if [ "$maclist_5g" = "" ]; then
			bh_maclist_5g="$3,$5"
		else
			[ "$exist_5g" -eq 0 ] && bh_maclist_5g="$maclist_5g,$3,$5"
		fi

		local bh_macnum_5g=$(echo $bh_maclist_5g | awk -F"," '{print NF}')

		if [ "$mgmt_2g" == "ccmp" ]; then
			pswd_2g=$(uci -q get wireless.$iface_2g.sae_password)
		fi

		if [ "$mgmt_5g" == "ccmp" ]; then
			pswd_5g=$(uci -q get wireless.$iface_5g.sae_password)
		fi

		ssid_2g=$(printf "%s" $ssid_2g | base64 | xargs)
		pswd_2g=$(printf "%s" $pswd_2g | base64 | xargs)
		ssid_5g=$(printf "%s" $ssid_5g | base64 | xargs)
		pswd_5g=$(printf "%s" $pswd_5g | base64 | xargs)

		case "$channel" in
			52|56|60|64|100|104|108|112|116|120|124|128|132|136|140|149|153|157|161|165)
				uci set wireless.$device_5g.channel='auto'
				uci commit wireless
				;;
			*) ;;
		esac

		#ignore CAC on first init
		radartool -i $device_5g disable

		local buff="{\"method\":\"init\",\"params\":{\"whc_role\":\"CAP\",\"bsd\":\"0\",\"ssid_2g\":\"${ssid_2g}\",\"pswd_2g\":\"${pswd_2g}\",\"mgmt_2g\":\"${mgmt_2g}\",\"ssid_5g\":\"${ssid_5g}\",\"pswd_5g\":\"${pswd_5g}\",\"mgmt_5g\":\"${mgmt_5g}\",\"bh_ssid\":\"${bh_ssid}\",\"bh_pswd\":\"${bh_pswd}\",\"bh_mgmt\":\"psk2\",\"bh_macnum_5g\":\"${bh_macnum_5g}\",\"bh_maclist_5g\":\"${bh_maclist_5g}\",\"bh_macnum_2g\":\"0\",\"bh_maclist_2g\":\"\"}}"

			mimesh_init "$buff"
	fi

		check_cap_init_status_v2 $name $1 $3 $5 $is_cable
}

do_re_dhcp() {
	local bridge="br-lan"
	local ifname=$(uci -q get misc.wireless.apclient_5G)
	local model=$(uci -q get misc.hardware.model)
	[ -z "$model" ] && model=$(cat /proc/xiaoqiang/model)

	#tcpdump -i wl11 port 47474 -w /tmp/aaa &
	iw dev $ifname set 4addr on >/dev/null 2>&1
	iwpriv ${ifname} wds 1
	brctl addif br-lan ${ifname}

	ifconfig br-lan 0.0.0.0

	#udhcpc on br-lan, for re init time optimization
	udhcpc -q -p /var/run/udhcpc-${bridge}.pid -s /usr/share/udhcpc/mesh_dhcp.script -f -t 0 -i $bridge -x hostname:MiWiFi-${model}

	exit $?
}

re_start_wps() {
	local ifname=$(uci -q get misc.wireless.apclient_5G)
	local ifname_5G=$(uci -q get misc.wireless.ifname_5G)
	local device=$(uci -q get misc.wireless.${ifname}_device)
	local channel="$2"

	eth_down

	wpa_supplicant_if_remove $ifname
	wlanconfig $ifname destroy -cfg80211

	case "$channel" in
		52|56|60|64|100|104|108|112|116|120|124|128|132|136|140|149|153|157|161|165) channel=36
			;;
		*) ;;
	esac

	cfg80211tool $ifname_5G channel $channel
	sleep 2

	wlanconfig $ifname create wlandev $device wlanmode sta -cfg80211
	iw dev $device interface add $ifname type __ap
	cfg80211tool $ifname channel $channel
	sleep 2

	rm -f /var/run/wpa_supplicant-${ifname}.conf
	echo -e "ctrl_interface=/var/run/wpa_supplicant\nctrl_interface_group=0\nupdate_config=1" | tee /var/run/wpa_supplicant-${ifname}.conf

	wpa_supplicant_if_add $ifname "br-lan"
	sleep 1

	wpa_cli -p /var/run/wpa_supplicant-$ifname -i $ifname wps_pbc "$1"

	for i in $(seq 1 60)
	do
		status=$(wpa_cli -p /var/run/wpa_supplicant-$ifname -i ${ifname} status | grep ^wpa_state= | cut -f2- -d=)
		if [ "$status" == "COMPLETED" ]; then
			#do_re_init $ifname $1
			exit 0
		fi
		sleep 2
	done

	eth_up

	wpa_supplicant_if_remove $ifname
	rm -f /var/run/wpa_supplicant-${ifname}.conf
	wlanconfig $ifname destroy -cfg80211
	wifi

	exit 1
}

cap_create_vap() {
	local ifname="$2"
	local device="$1"
	local channel="$3"
	local wifi_mode="$4"
	local ifname_5G=$(uci -q get misc.wireless.ifname_5G)
	local macaddr=$(cat /sys/class/net/br-lan/address)
	local uuid=$(echo "$macaddr" | sed 's/://g')
	local ssid=$(uci -q get wireless.@wifi-iface[0].ssid)
	local key=$(openssl rand -base64 8 | md5sum | cut -c1-32)
	local model=$(uci -q get misc.hardware.model)
	[ -z "$model" ] && model=$(cat /proc/xiaoqiang/model)

	cp -f /usr/share/mesh/hostapd-template.conf /var/run/hostapd-${ifname}.conf

	case "$channel" in
		52|56|60|64|100|104|108|112|116|120|124|128|132|136|140|149|153|157|161|165)
			channel=36
			if [ "$wifi_mode" = "11AHE160" -o "$wifi_mode" = "11ACVHT160" ]; then
				[ "$wifi_mode" = "11AHE160" ] && wifi_mode="11AHE80" || wifi_mode="11ACVHT80"
				cfg80211tool $ifname_5G mode $wifi_mode
				sleep 1
			fi
			;;
		*) ;;
	esac

	echo -e "interface=$ifname" >> /var/run/hostapd-${ifname}.conf
	echo -e "model_name=$model" >> /var/run/hostapd-${ifname}.conf
	[ -z "$channel" ] || echo -e "channel=$channel" >> /var/run/hostapd-${ifname}.conf
	echo -e "wpa_passphrase=$key" >> /var/run/hostapd-${ifname}.conf
	echo -e "ssid=$ssid" >> /var/run/hostapd-${ifname}.conf
	echo -e "uuid=87654321-9abc-def0-1234-$uuid" >> /var/run/hostapd-${ifname}.conf
	echo -e "ctrl_interface=/var/run/hostapd-$device" >> /var/run/hostapd-${ifname}.conf

	wlanconfig $ifname create wlandev $device wlanmode ap -cfg80211
	iw dev $device interface add $ifname type __ap
	[ -z "$channel" ] || cfg80211tool $ifname channel $channel
	[ -z "$wifi_mode" ] || cfg80211tool $ifname mode $wifi_mode

	for i in $(seq 1 10)
	do
		sleep 2
		local acs_state_son=$(iwpriv $ifname get_acs_state | cut -f2- -d ':')
		local acs_state_main=$(iwpriv $ifname_5G get_acs_state | cut -f2- -d ':')
		if [ $acs_state_son -eq 0 -a $acs_state_main -eq 0 ]; then
			break
		fi
	done

	hostapd /var/run/hostapd-${ifname}.conf &
}

cap_start_wps() {
	local ifname=$(uci -q get misc.wireless.mesh_ifname_5G)
	local device=$(uci -q get misc.wireless.if_5G)
	local status_file=$(echo $1 | sed s/[:]//g)
	local ifname_5G=$(uci -q get misc.wireless.ifname_5G)
	local wifi_mode=$(cfg80211tool "$ifname_5G" get_mode | awk -F':' '{print $2}')
	local channel=$(iwinfo "$ifname_5G" f | grep \* | awk '{print $5}' | sed 's/)//g')
	local netmode=$(uci -q get xiaoqiang.common.NETMODE)

	echo "init" > /tmp/${status_file}-status
	radartool -n -i $device ignorecac 1
	radartool -n -i $device disable
	sleep 2
	cap_create_vap "$device" "$ifname" "$channel" "$wifi_mode"
	sleep 2

	iwpriv $ifname miwifi_mesh 2
	iwpriv $ifname miwifi_mesh_mac $1

	cfg80211tool $ifname maccmd_sec 3
	cfg80211tool $ifname addmac_sec $2
	cfg80211tool $ifname maccmd_sec 1

	hostapd_cli -i $ifname -p /var/run/hostapd-${device} -P /var/run/hostapd_cli-${ifname}.pid update_beacon
	hostapd_cli -i $ifname -p /var/run/hostapd-${device} -P /var/run/hostapd_cli-${ifname}.pid wps_pbc

	for i in $(seq 1 60)
	do
		wps_status=$(hostapd_cli -i ${ifname} -p /var/run/hostapd-${device} -P /var/run/hostapd_cli-${ifname}.pid wps_get_status | grep 'Last\ WPS\ result:' | cut -f4- -d ' ')
		pbc_status=$(hostapd_cli -i ${ifname} -p /var/run/hostapd-${device} -P /var/run/hostapd_cli-${ifname}.pid wps_get_status | grep 'PBC\ Status:' | cut -f3- -d ' ')
		if [ "$wps_status" == "Success" ]; then
			if [ "$pbc_status" == "Disabled" ]; then
				echo "connected" > /tmp/${status_file}-status
				cap_disable_wps_trigger  $device $ifname

				radartool -n -i $device enable
				radartool -n -i $device ignorecac 0

				exit 0
			fi
		fi
		sleep 2
	done

	#cap_close_wps
	cap_delete_vap
	echo "failed" > /tmp/${status_file}-status

	radartool -n -i $device enable
	radartool -n -i $device ignorecac 0

	case "$channel" in
		52|56|60|64|100|104|108|112|116|120|124|128|132|136|140|149|153|157|161|165)
			cfg80211tool $ifname_5G channel $channel
			if [ "$wifi_mode" = "11AHE160" -o "$wifi_mode" = "11ACVHT160" ]; then
				cfg80211tool $ifname_5G mode $wifi_mode
			fi
			;;
		*) ;;
	esac

	exit 1
}

case "$1" in
	re_start)
	re_start_wps "$2" "$3"
	;;
	cap_start)
	cap_start_wps "$2" "$3"
	;;
	cap_close)
	cap_close_wps
	;;
	init_cap)
	init_cap_mode
	;;
	cap_init)
	run_with_lock do_cap_init "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9"
	;;
	cap_init_bsd)
	do_cap_init_bsd "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9"
	;;
	re_init)
	run_with_lock do_re_init "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "$10" "$11"
	;;
	re_init_bsd)
	do_re_init_bsd "$2" "$3" "$4" "$5" "$6" "$7" "$8"
	;;
	re_dhcp)
	do_re_dhcp
	;;
	cap_create)
	cap_create_vap "$2" "$3"
	;;
	cap_clean)
	cap_clean_vap "$2" "$3"
	;;
	re_clean)
	re_clean_vap
	;;
	re_init_json)
	do_re_init_json "$2"
	;;
	*)
	usage
	;;
esac
