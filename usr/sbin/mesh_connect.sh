#!/bin/sh
# Copyright (C) 2020 Xiaomi

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

re_clean_vap() {
	local ifname=$(uci -q get misc.wireless.apclient_5G)

	killall -9 wpa_supplicant
	wlanconfig $ifname destroy -cfg80211
	rm -f /var/run/wpa_supplicant-${ifname}.conf
	wpa_supplicant -g /var/run/wpa_supplicantglobal -B -P /var/run/wpa_supplicant-global.pid

	local lanip=$(uci -q get network.lan.ipaddr)
	if [ "$lanip" != "" ]; then
		ifconfig br-lan $lanip
	else
		ifconfig br-lan 192.168.31.1
	fi

	eth_up
	wifi
}

check_re_init_status() {
	for i in $(seq 1 60)
	do
		whcal totalcheck > /dev/null 2>&1
		if [ $? = 0 ]; then
			whc_ual "{\"method\":\"postinit\"}"
			/etc/init.d/meshd stop
			eth_up
			exit 0

			#uci set wireless.@wifi-iface[1].miwifi_mesh=0
			#uci commit wireless

			#iwpriv $ifname_2g miwifi_mesh 0
			#hostapd_cli -i $ifname_2g -p /var/run/hostapd-${device} -P /var/run/hostapd_cli-${ifname_2g}.pid update_beacon
		fi
		sleep 2
	done

	eth_up

	exit 1
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

	killall -9 wpa_supplicant
	wlanconfig $ifname destroy -cfg80211
	rm -f /var/run/wpa_supplicant-${ifname}.conf
	wpa_supplicant -g /var/run/wpa_supplicantglobal -B -P /var/run/wpa_supplicant-global.pid

	touch /tmp/bh_maclist_5g
	#touch /tmp/bh_maclist_2g
	local bh_maclist_5g=$(cat /tmp/bh_maclist_5g | sed 's/ /,/g')
	#local bh_maclist_2g=$(cat /tmp/bh_maclist_2g | sed 's/ /,/g')
	local bh_macnum_5g=$(echo $bh_maclist_5g | awk -F"," '{print NF}')
	#local bh_macnum_2g=$(echo $bh_maclist_2g | awk -F"," '{print NF}')

	do_re_init_json

	local buff="{\"method\":\"init\",\"params\":{\"whc_role\":\"RE\",\"bsd\":\"0\",\"ssid_2g\":\"${ssid_2g}\",\"pswd_2g\":\"${pswd_2g}\",\"mgmt_2g\":\"${mgmt_2g}\",\"ssid_5g\":\"${ssid_5g}\",\"pswd_5g\":\"${pswd_5g}\",\"mgmt_5g\":\"${mgmt_5g}\",\"bh_ssid\":\"${bh_ssid}\",\"bh_pswd\":\"${bh_pswd}\",\"bh_mgmt\":\"${bh_mgmt}\",\"bh_macnum_5g\":\"${bh_macnum_5g}\",\"bh_maclist_5g\":\"${bh_maclist_5g}\",\"bh_macnum_2g\":\"0\",\"bh_maclist_2g\":\"\"}}"
	whc_ual "$buff"
	sleep 2

	check_re_init_status
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

	killall -9 wpa_supplicant
	wlanconfig $ifname destroy -cfg80211
	rm -f /var/run/wpa_supplicant-${ifname}.conf
	wpa_supplicant -g /var/run/wpa_supplicantglobal -B -P /var/run/wpa_supplicant-global.pid

	touch /tmp/bh_maclist_5g
	#touch /tmp/bh_maclist_2g
	local bh_maclist_5g=$(cat /tmp/bh_maclist_5g | sed 's/ /,/g')
	#local bh_maclist_2g=$(cat /tmp/bh_maclist_2g | sed 's/ /,/g')
	local bh_macnum_5g=$(echo $bh_maclist_5g | awk -F"," '{print NF}')
	#local bh_macnum_2g=$(echo $bh_maclist_2g | awk -F"," '{print NF}')

	do_re_init_json

	local buff="{\"method\":\"init\",\"params\":{\"whc_role\":\"RE\",\"whc_ssid\":\"${whc_ssid}\",\"whc_pswd\":\"${whc_pswd}\",\"whc_mgmt\":\"${whc_mgmt}\",\"bh_ssid\":\"${bh_ssid}\",\"bh_pswd\":\"${bh_pswd}\",\"bh_mgmt\":\"${bh_mgmt}\",\"bh_macnum_5g\":\"${bh_macnum_5g}\",\"bh_maclist_5g\":\"${bh_maclist_5g}\",\"bh_macnum_2g\":\"0\",\"bh_maclist_2g\":\"\"}}"
	whc_ual "$buff"
	sleep 2

	check_re_init_status
}

do_re_init_json() {
	local jsonbuf=$(cat /tmp/extra_wifi_param 2>/dev/null)
	[ -z "$jsonbuf" ] && return

	. /lib/xqwhc/xqwhc_public.sh

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

	local support160=$(json_get_value "$jsonbuf" "support160")

	uci set wireless.wifi0.channel="$ch_5g"
	uci set wireless.wifi1.channel="$ch_2g"

	uci set wireless.wifi0.ax="$ax_5g"
	uci set wireless.wifi1.ax="$ax_2g"

	uci set wireless.wifi0.txpwr="$txpwr_5g"
	uci set wireless.wifi1.txpwr="$txpwr_2g"

	uci set wireless.wifi0.txbf="$txbf_5g"
	uci set wireless.wifi1.txbf="$txbf_2g"

	uci set wireless.wifi1.bw="$bw_2g"
	if [ "$support160" = "1" ]; then
		uci set wireless.wifi0.bw="$bw_5g"
	else
		if [ "$bw_5g" = "0" ]; then
			uci set wireless.wifi0.bw='80'
		else
			uci set wireless.wifi0.bw="$bw_5g"
		fi
	fi

	uci set wireless.@wifi-iface[1].hidden="$hidden_2g"
	uci set wireless.@wifi-iface[0].hidden="$hidden_5g"

	uci set wireless.@wifi-iface[0].disabled="$disabled_2g"
	uci set wireless.@wifi-iface[1].disabled="$disabled_5g"

	uci commit wireless
}

init_cap_mode() {
	/etc/init.d/meshd stop
	uci set wireless.@wifi-iface[0].miwifi_mesh=0
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

check_cap_init_status() {
	local ifname=$(uci -q get misc.backhauls.backhaul_5g_ap_iface)

	for i in $(seq 1 60)
	do
		whcal totalcheck > /dev/null 2>&1
		if [ $? = 0 ]; then
			whc_ual "{\"method\":\"postinit\"}"
			sleep 2
			init_done=1
			break
		fi
		sleep 2
	done

	if [ $init_done -eq 1 ]; then
		. /lib/xqwhc/xqwhc_hyt.sh
		for i in $(seq 1 90)
		do
			local assoc_count1=$(iwinfo $ifname a | grep -i -c $3)
			local assoc_count2=$(iwinfo $ifname a | grep -i -c $4)
			local assoc_hyt=0
			local hyd_pid=$(pgrep -x /usr/sbin/hyd)
			if [ -n "$hyd_pid" ]; then
				__hyt_info_local 'td s'
				assoc_hyt=$(echo "$info" | grep -i -c "$2")
			fi
			if [ $assoc_count1 -gt 0 -o $assoc_count2 -gt 0 -o $assoc_hyt -gt 0 ]; then
				/sbin/cap_push_backhaul_whitelist.sh
				echo "success" > /tmp/$1-status
				exit 0
			fi
			sleep 2
		done
	fi

	echo "failed" > /tmp/$1-status
	exit 1
}

do_cap_init_bsd() {
	local name=$(echo $1 | sed s/[:]//g)
	local whc_ssid=$(uci -q get wireless.@wifi-iface[1].ssid)
	local whc_pswd=$(uci -q get wireless.@wifi-iface[1].key)
	#local whc_mac=$(uci -q get wireless.wifi1.macaddr)
	local whc_mgmt=$(uci -q get wireless.@wifi-iface[1].encryption)

	local ifname=$(uci -q get misc.wireless.mesh_ifname_5G)
	local ifname_5g=$(uci -q get misc.backhauls.backhaul_5g_ap_iface)
	local ifname_2g=$(uci -q get misc.backhauls.backhaul_2g_ap_iface)
	local bh_ssid=$(printf "%s" $6 | base64 -d)
	local bh_pswd=$(printf "%s" $7 | base64 -d)
	local init_done=0

	local channel=$(uci -q get wireless.wifi0.channel)
	local bw=$(uci -q get wireless.wifi0.bw)

	local bh_maclist_5g=
	local bh_maclist_2g=

	echo "syncd" > /tmp/${name}-status
	cap_delete_vap

	local mode=$(uci -q get xiaoqiang.common.NETMODE)

	local backhaul_5G_index=$(uci show wireless|grep "$ifname_5g"|awk -F "." '{print $2}')
	#local backhaul_2G_index=$(expr $backhaul_5G_index + 1)

	local maclist_5g=$(uci -q get wireless.$backhaul_5G_index.maclist | sed 's/ /,/g')
	#local maclist_2g=$(uci -q get wireless.@wifi-iface[$backhaul_2G_index].maclist | sed 's/ /,/g')
	#local exist_2g=$(echo $maclist_2g | grep -i -c $2)
	local exist_5g=$(echo $maclist_5g | grep -i -c $3)

	if [ "whc_cap" = "$mode" ]; then
		[ "$exist_5g" -eq 0 ] && {
			cfg80211tool $ifname_5g addmac_sec $3
			cfg80211tool $ifname_5g addmac_sec $5
			cfg80211tool $ifname_5g maccmd_sec 1

			uci -q add_list wireless.$backhaul_5G_index.maclist=$3
			uci -q add_list wireless.$backhaul_5G_index.maclist=$5
			uci commit wireless
		}
		#[ "$exist_2g" -eq 0 ] && {
		#	cfg80211tool $ifname_2g addmac_sec $2
		#	cfg80211tool $ifname_2g addmac_sec $4
		#	cfg80211tool $ifname_2g maccmd_sec 1

		#	uci -q add_list wireless.@wifi-iface[$backhaul_2G_index].maclist=$2
		#	uci -q add_list wireless.@wifi-iface[$backhaul_2G_index].maclist=$4
		#}
	else
		if [ "$maclist_5g" = "" ]; then
			bh_maclist_5g="$3,$5"
		else
			[ "$exist_5g" -eq 0 ] && bh_maclist_5g="$maclist_5g,$3,$5"
		fi

		#if [ "$maclist_2g" = "" ]; then
		#	bh_maclist_2g="$2,$4"
		#else
		#	[ "$exist_2g" -eq 0 ] && bh_maclist_2g="$maclist_2g,$2,$4"
		#fi

		local bh_macnum_5g=$(echo $bh_maclist_5g | awk -F"," '{print NF}')
		#local bh_macnum_2g=$(echo $bh_maclist_2g | awk -F"," '{print NF}')

		if [ "$whc_mgmt" == "ccmp" ]; then
			whc_pswd=$(uci -q get wireless.@wifi-iface[1].sae_password)
		fi

		whc_ssid=$(printf "%s" $whc_ssid | base64 | xargs)
		whc_pswd=$(printf "%s" $whc_pswd | base64 | xargs)

		case "$channel" in
			52|56|60|64)
				if [ "$bw" -eq 0 ]; then
					uci set wireless.wifi0.channel='36'
				else
					uci set wireless.wifi0.channel='auto'
				fi
				uci commit wireless
				;;
			*) ;;
		esac

		local buff="{\"method\":\"init\",\"params\":{\"whc_role\":\"CAP\",\"whc_ssid\":\"${whc_ssid}\",\"whc_pswd\":\"${whc_pswd}\",\"whc_mgmt\":\"${whc_mgmt}\",\"bh_ssid\":\"${bh_ssid}\",\"bh_pswd\":\"${bh_pswd}\",\"bh_mgmt\":\"psk2\",\"bh_macnum_5g\":\"${bh_macnum_5g}\",\"bh_maclist_5g\":\"${bh_maclist_5g}\",\"bh_macnum_2g\":\"0\",\"bh_maclist_2g\":\"\"}}"
		whc_ual "$buff"
	fi

	check_cap_init_status $name $1 $3 $5
}

do_cap_init() {
	local name=$(echo $1 | sed s/[:]//g)
	local ssid_2g=$(uci -q get wireless.@wifi-iface[1].ssid)
	local pswd_2g=$(uci -q get wireless.@wifi-iface[1].key)
	local mgmt_2g=$(uci -q get wireless.@wifi-iface[1].encryption)
	local ssid_5g=$(uci -q get wireless.@wifi-iface[0].ssid)
	local pswd_5g=$(uci -q get wireless.@wifi-iface[0].key)
	local mgmt_5g=$(uci -q get wireless.@wifi-iface[0].encryption)

	local ifname=$(uci -q get misc.wireless.mesh_ifname_5G)
	local ifname_5g=$(uci -q get misc.backhauls.backhaul_5g_ap_iface)
	local ifname_2g=$(uci -q get misc.backhauls.backhaul_2g_ap_iface)
	local bh_ssid=$(printf "%s" $6 | base64 -d)
	local bh_pswd=$(printf "%s" $7 | base64 -d)
	local init_done=0

	local channel=$(uci -q get wireless.wifi0.channel)
	local bw=$(uci -q get wireless.wifi0.bw)

	local bh_maclist_5g=
	local bh_maclist_2g=

	echo "syncd" > /tmp/${name}-status
	cap_delete_vap

	local mode=$(uci -q get xiaoqiang.common.NETMODE)
	local backhaul_5G_index=$(uci show wireless|grep $ifname_5g|awk -F "." '{print $2}')
	#local backhaul_2G_index=$(expr $backhaul_5G_index + 1)

	local maclist_5g=$(uci -q get wireless.$backhaul_5G_index.maclist | sed 's/ /,/g')
	#local maclist_2g=$(uci -q get wireless.@wifi-iface[$backhaul_2G_index].maclist | sed 's/ /,/g')
	#local exist_2g=$(echo $maclist_2g | grep -i -c $2)
	local exist_5g=$(echo $maclist_5g | grep -i -c $3)

	if [ "whc_cap" = "$mode" ]; then
		[ "$exist_5g" -eq 0 ] && {
			cfg80211tool $ifname_5g addmac_sec $3
			cfg80211tool $ifname_5g addmac_sec $5
			cfg80211tool $ifname_5g maccmd_sec 1

			uci -q add_list wireless.$backhaul_5G_index.maclist=$3
			uci -q add_list wireless.$backhaul_5G_index.maclist=$5
			uci commit wireless
		}
		#[ "$exist_2g" -eq 0 ] && {
		#	cfg80211tool $ifname_2g addmac_sec $2
		#	cfg80211tool $ifname_2g addmac_sec $4
		#	cfg80211tool $ifname_2g maccmd_sec 1

		#	uci -q add_list wireless.@wifi-iface[$backhaul_2G_index].maclist=$2
		#	uci -q add_list wireless.@wifi-iface[$backhaul_2G_index].maclist=$4
		#}
	else
		if [ "$maclist_5g" = "" ]; then
			bh_maclist_5g="$3,$5"
		else
			[ "$exist_5g" -eq 0 ] && bh_maclist_5g="$maclist_5g,$3,$5"
		fi

		#if [ "$maclist_2g" = "" ]; then
		#	bh_maclist_2g="$2,$4"
		#else
		#	[ "$exist_2g" -eq 0 ] && bh_maclist_2g="$maclist_2g,$2,$4"
		#fi

		local bh_macnum_5g=$(echo $bh_maclist_5g | awk -F"," '{print NF}')
		#local bh_macnum_2g=$(echo $bh_maclist_2g | awk -F"," '{print NF}')

		if [ "$mgmt_2g" == "ccmp" ]; then
			pswd_2g=$(uci -q get wireless.@wifi-iface[1].sae_password)
		fi

		if [ "$mgmt_5g" == "ccmp" ]; then
			pswd_5g=$(uci -q get wireless.@wifi-iface[0].sae_password)
		fi

		ssid_2g=$(printf "%s" $ssid_2g | base64 | xargs)
		pswd_2g=$(printf "%s" $pswd_2g | base64 | xargs)
		ssid_5g=$(printf "%s" $ssid_5g | base64 | xargs)
		pswd_5g=$(printf "%s" $pswd_5g | base64 | xargs)

		case "$channel" in
			52|56|60|64)
				if [ "$bw" -eq 0 ]; then
					uci set wireless.wifi0.channel='36'
				else
					uci set wireless.wifi0.channel='auto'
				fi
				uci commit wireless
				;;
			*) ;;
		esac

		local buff="{\"method\":\"init\",\"params\":{\"whc_role\":\"CAP\",\"bsd\":\"0\",\"ssid_2g\":\"${ssid_2g}\",\"pswd_2g\":\"${pswd_2g}\",\"mgmt_2g\":\"${mgmt_2g}\",\"ssid_5g\":\"${ssid_5g}\",\"pswd_5g\":\"${pswd_5g}\",\"mgmt_5g\":\"${mgmt_5g}\",\"bh_ssid\":\"${bh_ssid}\",\"bh_pswd\":\"${bh_pswd}\",\"bh_mgmt\":\"psk2\",\"bh_macnum_5g\":\"${bh_macnum_5g}\",\"bh_maclist_5g\":\"${bh_maclist_5g}\",\"bh_macnum_2g\":\"0\",\"bh_maclist_2g\":\"\"}}"
		whc_ual "$buff"
	fi

	check_cap_init_status $name $1 $3 $5
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

	wlanconfig $ifname destroy -cfg80211
	killall -9 wpa_supplicant

	case "$channel" in
		52|56|60|64) channel=36
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

	wpa_supplicant -g /var/run/wpa_supplicantglobal -B -P /var/run/wpa_supplicant-global.pid
	wpa_supplicant -i $ifname -Dnl80211 -c /var/run/wpa_supplicant-${ifname}.conf -B
	sleep 1

	wpa_cli -i $ifname wps_pbc "$1"

	for i in $(seq 1 60)
	do
		status=$(wpa_cli -i ${ifname} status | grep ^wpa_state= | cut -f2- -d=)
		if [ "$status" == "COMPLETED" ]; then
			#do_re_init $ifname $1
			exit 0
		fi
		sleep 2
	done

	eth_up

	wlanconfig $ifname destroy -cfg80211
	killall -9 wpa_supplicant
	rm -f /var/run/wpa_supplicant-${ifname}.conf
	rm -f /var/run/wpa_supplicant-global.pid
	wpa_supplicant -g /var/run/wpa_supplicantglobal -B -P /var/run/wpa_supplicant-global.pid
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
		52|56|60|64)
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
		52|56|60|64)
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
	do_cap_init "$2" "$3" "$4" "$5" "$6" "$7" "$8"
	;;
	cap_init_bsd)
	do_cap_init_bsd "$2" "$3" "$4" "$5" "$6" "$7" "$8"
	;;
	re_init)
	do_re_init "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "$10"
	;;
	re_init_bsd)
	do_re_init_bsd "$2" "$3" "$4" "$5" "$6" "$7"
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
