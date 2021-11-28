#!/bin/sh 

# mimesh upper abstract layer support

. /lib/mimesh/mimesh_public.sh

nw_cfg="/tmp/log/nw_cfg"

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
	MIMESH_LOGI " setup wifi cfg on CAP "

	local iface_list="" ii=0 iface_idx_start=2
	local main_ssid main_mgmt main_pswd
	ifconfig wifi2 >/dev/null 2>&1 && export WIFI2_EXIST=1 || export WIFI2_EXIST=0
	#[ "$WIFI2_EXIST" = "1" ] && iface_idx_start=3 || iface_idx_start=2
	[ -e /etc/config/wireless ] && iface_idx_start=$(cat /etc/config/wireless | grep -c -w 'config wifi-iface')

	# detect 5g wifi-iface index
	local ifname_5g=$(uci -q get misc.wireless.iface_5g_ifname)
	local iface_5g=$(uci show wireless | grep -w "ifname=\'$ifname_5g\'" | awk -F"." '{print $2}')
	local iface_5g_index=$(uci show wireless |grep -w "ifname=\'$ifname_5g\'" | cut -d '[' -f2 | cut -d ']' -f1)

	# wifi ap ifaces
	iface_list="0 1"
	for ii in ${iface_list}; do
		if [ "$bsd" -eq 0 ]; then
			[ "$ii" -eq "$iface_5g_index" ] && {
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

	local bh_ifname="`uci get misc.backhauls.backhaul_5g_ap_iface`"
	ii=$iface_idx_start

	local device_5g=$(uci -q get misc.wireless.if_5G)
	local lanmac=$(ifconfig br-lan | grep HWaddr | awk '{print $5}')

	uci -q batch <<-EOF >/dev/null
add wireless wifi-iface
set wireless.@wifi-iface[$ii].device="$device_5g"
set wireless.@wifi-iface[$ii].ifname="$bh_ifname"
set wireless.@wifi-iface[$ii].network='lan'
set wireless.@wifi-iface[$ii].mode='ap'
set wireless.@wifi-iface[$ii].channel_block_list='52,56,60,64,149,153,157,161,165'
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
set wireless.@wifi-iface[$ii].athnewind='1'
set wireless.@wifi-iface[$ii].mesh_ver='2'
set wireless.@wifi-iface[$ii].mesh_apmac="$lanmac"
set wireless.@wifi-iface[$ii].mesh_aplimit='9'
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

	# set bsd
	[ "$bsd" -eq 1 ] && {
		uci -q set wireless.@wifi-iface[0].bsd='1'
		uci -q set wireless.@wifi-iface[1].bsd='1'
	}
	uci -q set wireless.@wifi-iface[0].miwifi_mesh='0'
	uci -q set wireless.$iface_5g.channel_block_list='52,56,60,64,149,153,157,161,165'
	uci -q set wireless.$device_5g.CSwOpts='0x31'

	uci commit wireless
}

# netmode: 1 setmode 0 clearmode
# mode: whc_cap/whc_re is used for trafficd tbus
__set_netmode()
{
	local swt="$1"
	local netmode=$(uci -q get xiaoqiang.common.NETMODE)

	# netmode
	if [ "$swt" -eq 0 ]; then
		uci -q delete xiaoqiang.common.NETMODE
		nvram set mode=Router
	else
		if [ "$2" = "cap" ]; then
			if [ "$netmode" = "wifiapmode" -o "$netmode" = "lanapmode" ]; then
				uci -q set xiaoqiang.common.CAP_MODE="ap"
			else
				uci -q set xiaoqiang.common.NETMODE="whc_cap"
			fi
		else
			local mode="whc_$2"
			uci -q set xiaoqiang.common.NETMODE="$mode"
			[ "$2" = "re" ] && nvram set mode=AP
		fi
	fi

	uci commit xiaoqiang
	nvram commit

	return 0
}

## network cfg init on RE
__init_network_re()
{
	MIMESH_LOGI " setup network cfg on $whc_role "

	uci -q set dhcp.lan.ignore=1
	uci commit dhcp
	# until whc init, we add if to bridge
	uci -q set network.lan.ifname='eth1 eth2 eth3 eth4';
	uci -q set network.lan.proto=dhcp
	uci -q set network.lan.type=bridge
	uci -q delete network.lan.ipaddr
	uci -q delete network.lan.netmask
	uci -q delete network.lan.gateway
	uci -q delete network.lan.dns
	uci -q delete network.lan.mtu
	uci commit network

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
			local cap_mode=$(uci -q get xiaoqiang.common.CAP_MODE)
			#local model=$(uci -q get misc.hardware.model)
			#[ -z "$model" ] && model=$(cat /proc/xiaoqiang/model)
			#local hostname="MiWiFi-$model"
			MIMESH_LOGI " @@@@@@ ============ mesh re set ip=$ip gw=$router."

			uci -q set xiaoqiang.common.ap_hostname=$hostname
			if [ "$cap_mode" != "ap" ] ; then
				uci -q set xiaoqiang.common.vendorinfo="$vendorinfo"
			fi  
			uci commit xiaoqiang
			uci -q set network.lan=interface
			uci -q set network.lan.type=bridge
			uci -q set network.lan.proto=dhcp
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

	# no wan on son re, so delete wan
	uci -q delete network.wan
	uci -q delete network.wan6
	uci commit network

	local model=$(uci -q get misc.hardware.model)
	if [ "$model" = "RA72" -o "$model" = "RA74" ]; then
		uci -q batch <<EOF
set network.switch0.max_frame_size=1522
set network.switch1.enable_vlan=1
delete network.@switch_vlan[1]
delete network.@switch_vlan[0]
add network switch_vlan
set network.@switch_vlan[0].device='switch1'
set network.@switch_vlan[0].vlan='3'
set network.@switch_vlan[0].ports='1 4t'
add network switch_vlan
set network.@switch_vlan[1].device='switch1'
set network.@switch_vlan[1].vlan='4'
set network.@switch_vlan[1].ports='2 4t'
add network switch_vlan
set network.@switch_vlan[2].device='switch1'
set network.@switch_vlan[2].vlan='5'
set network.@switch_vlan[2].ports='3 4t'
set network.lan.ifname='eth0.3 eth0.4 eth0.5 eth1'
commit network
EOF
		/etc/init.d/network reconfig_switch
		vconfig add eth0 3
		vconfig add eth0 4
		vconfig add eth0 5
	fi

	ifdown vpn 2>/dev/null
	/usr/sbin/vasinfo_fw.sh off 2>/dev/null
	[ -f /etc/init.d/hwnat ] && /etc/init.d/hwnat off 2>/dev/null
	/etc/init.d/trafficd stop
	/etc/init.d/odhcpd stop

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
	MIMESH_LOGI " setup wifi cfg on $whc_role "

	local device_5g=$(uci -q get misc.wireless.if_5G)
	local ifname_5g=$(uci -q get misc.wireless.ifname_5G)
	local iface_5g=$(uci show wireless | grep -w "ifname=\'$ifname_5g\'" | awk -F"." '{print $2}')

	# wifi, do NOT auto create wifi vap by repacd, setup vap and key parameters by user define
	uci -q set wireless.$device_5g.CSwOpts='0x31'
	ifconfig wifi2 >/dev/null 2>&1 && export WIFI2_EXIST=1 || export WIFI2_EXIST=0

	local iface_list="" ii=0 idx=0 iface_idx_start=2
	local main_ssid main_mgmt main_pswd
	#[ "$WIFI2_EXIST" = "1" ] && iface_idx_start=3 || iface_idx_start=2
	[ -e /etc/config/wireless ] && iface_idx_start=$(cat /etc/config/wireless | grep -c -w 'config wifi-iface')

	# detect 5g wifi-iface index
	local ifname_5g=$(uci -q get misc.wireless.iface_5g_ifname)
	local iface_5g_index=$(uci show wireless |grep -w "ifname=\'$ifname_5g\'" | cut -d '[' -f2 | cut -d ']' -f1)

	# config wifi ap ifaces
	iface_list="0 1"
	for ii in ${iface_list}; do
		if [ "$bsd" -eq 0 ]; then
			[ "$ii" -eq "$iface_5g_index" ] && {
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
	ii=$iface_idx_start
	local bh_ifname=$(uci get misc.backhauls.backhaul_5g_ap_iface)
	local lanmac=$(ifconfig br-lan | grep HWaddr | awk '{print $5}')
	uci -q batch <<-EOF >/dev/null
add wireless wifi-iface
set wireless.@wifi-iface[$ii].device="$device_5g"
set wireless.@wifi-iface[$ii].ifname="$bh_ifname"
set wireless.@wifi-iface[$ii].network='lan'
set wireless.@wifi-iface[$ii].mode='ap'
set wireless.@wifi-iface[$ii].channel_block_list='52,56,60,64,149,153,157,161,165'
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
set wireless.@wifi-iface[$ii].athnewind='1'
set wireless.@wifi-iface[$ii].mesh_ver='2'
set wireless.@wifi-iface[$ii].mesh_apmac="$lanmac"
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

	# setup 5G ind bh sta ifaces
	local bh_sta_ifname=$(uci get misc.backhauls.backhaul_5g_sta_iface)
	ii=$(($iface_idx_start + 1))
	uci -q batch <<-EOF >/dev/null
add wireless wifi-iface
set wireless.@wifi-iface[$ii]=wifi-iface
set wireless.@wifi-iface[$ii].device="$device_5g"
set wireless.@wifi-iface[$ii].ifname="$bh_sta_ifname"
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
set wireless.@wifi-iface[$ii].disabled='$eth_init'
set wireless.@wifi-iface[$ii].backhaul='1'
set wireless.@wifi-iface[$ii].group='0'
set wireless.@wifi-iface[$ii].athnewind='1'
EOF
	# set bsd
	[ "$bsd" -eq 1 ] && {
		uci -q set wireless.@wifi-iface[0].bsd='1'
		uci -q set wireless.@wifi-iface[1].bsd='1'
	}
	uci -q set wireless.$iface_5g.miwifi_mesh='0'
	uci -q set wireless.$iface_5g.channel_block_list='52,56,60,64,149,153,157,161,165'

	uci commit wireless
}

## check if wifi has config backhaul
# 2 : uninit
# 1: init and wifi cfg change (ssid + key)
# 0: init and wifi cfg NO change
export WIFI_UNINIT=2
export WIFI_INIT_CHANGE=1   #init change need a restore
export WIFI_INIT_NOCHANGE=0
# only call before next cap/re retry, thus we can save wifi up time
mimesh_preinit()
{
	local role="$1"
	MIMESH_LOGI "*preinit"

	ret=$WIFI_INIT_NOCHANGE

	local netmode=$(uci -q get xiaoqiang.common.NETMODE)
	if [ $ret -eq $WIFI_INIT_NOCHANGE ]; then
		if [ "$role" = "cap" -o "$role" = "CAP" ]; then
			[ "$netmode" = "whc_cap" ] || {
				[ "$netmode" = "wifiapmode" -o "$netmode" = "lanapmode" ] && {
					[ "`uci -q get xiaoqiang.common.CAP_MODE`" = "ap" ] || {
						ret=$WIFI_INIT_CHANGE
					}
				} || {
					ret=$WIFI_INIT_CHANGE
				}
			}
		fi
	fi

	MIMESH_LOGI "*preinit done, ret=$ret"
	return $ret
}

__init_cap()
{
	MIMESH_LOGI " __init_cap: continue..."

	__set_netmode 1 cap

	__init_wifi_cap

	/etc/init.d/network restart

	return 0
}

__init_re()
{
	MIMESH_LOGD " __init_re: continue..."

	__set_netmode 1 re

	__init_network_re
	__init_wifi_re

	/etc/init.d/network restart

	return 0
}

# check if ssid & encryption & key changed
# 1: wifi cfg changed
# 0: wifi cfg NO change
__check_wifi_cfg_no_changed()
{
	local key word word_cur

	local ifname_2g=$(uci -q get misc.wireless.ifname_2G)
	local iface_2g=$(uci show wireless | grep -w "ifname=\'$ifname_2g\'" | awk -F"." '{print $2}')
	local ifname_5g=$(uci -q get misc.wireless.ifname_5G)
	local iface_5g=$(uci show wireless | grep -w "ifname=\'$ifname_5g\'" | awk -F"." '{print $2}')

	local ssid_5g_cur="`uci -q get wireless.$iface_5g.ssid`"
	local mgmt_5g_cur="`uci -q get wireless.$iface_5g.encryption`"
	local pswd_5g_cur="`uci -q get wireless.$iface_5g.key`"
	local ssid_2g_cur="`uci -q get wireless.$iface_2g.ssid`"
	local mgmt_2g_cur="`uci -q get wireless.$iface_2g.encryption`"
	local pswd_2g_cur="`uci -q get wireless.$iface_2g.key`"
	local key_lists="ssid_5g mgmt_5g pswd_5g ssid_2g mgmt_2g pswd_2g"
	for key in $key_lists; do
		if [ "$bsd" -eq 0 ]; then
			word="`eval echo '$'"$key"`"
		else
			word="`eval echo '$'"whc_${key:0:4}"`"
		fi
		word_cur="`eval echo '$'"${key}_cur"`"
		[ "$word" != "$word_cur" ] && {
			MIMESH_LOGI "      wifi init with cfg changed, [$word_cur]->[$word]"
			MIMESH_LOGI "      [$ssid_5g_cur][$mgmt_5g_cur][$pswd_5g_cur][$ssid_2g_cur][$mgmt_2g_cur][$pswd_2g_cur]->"
			[ "$bsd" -eq 0 ] && {
				MIMESH_LOGI "      [$ssid_5g][$mgmt_5g][$pswd_5g][$ssid_2g][$mgmt_2g][$pswd_2g]"
			} || {
				MIMESH_LOGI "      [$whc_ssid][$whc_mgmt][$whc_pswd]"
			}
			return 1
		}
	done

	return 0
}

__mimesh_check_wireless()
{
	local device=$(uci -q get misc.wireless.if_5G)
	local ifname_5g=$(uci -q get misc.wireless.ifname_5G)
	local backhaul_5g=$(uci -q get misc.backhauls.backhaul_5g_ap_iface)

	for i in $(seq 1 3)
	do
		local state=$(hostapd_cli -p /var/run/hostapd-${device} -i ${ifname_5g} status | grep 'state' | cut -d '=' -f2)
		local check_again=false
		if [ "$state" != "ENABLED" ]; then
			hostapd_cli -p /var/run/hostapd-${device} -i ${ifname_5g} disable
			hostapd_cli -p /var/run/hostapd-${device} -i ${ifname_5g} enable
			check_again=true
		fi

		state=$(hostapd_cli -p /var/run/hostapd-${device} -i ${backhaul_5g} status | grep 'state' | cut -d '=' -f2)
		if [ "$state" != "ENABLED" ]; then
			hostapd_cli -p /var/run/hostapd-${device} -i ${backhaul_5g} disable
			hostapd_cli -p /var/run/hostapd-${device} -i ${backhaul_5g} enable
			check_again=true
		fi

		if [ $check_again == true ]; then
			sleep 5
		else
			break
		fi
	done
}

mimesh_init_done()
{
	local role="$1"
	MIMESH_LOGI " config init done. postpone handle mi services."
	uci -q set xiaoqiang.common.INITTED=YES
	uci commit xiaoqiang

	# turn off web init redirect page
	/usr/sbin/sysapi webinitrdr set off &

	# set wps state for qca wifi
	/usr/sbin/set_wps_state 2 &

	#ubus call check_wan blink_off

	if [ "$role" = "re" ]; then
		(/etc/init.d/firewall stop;/etc/init.d/firewall disable) &
		/etc/init.d/meshd stop
		__mimesh_check_wireless
	fi

	if [ "$role" = "cap" ]; then
		# for CAP, led blue on after init
		led_check && gpio_led blue off || gpio_led blue on

		/etc/init.d/firewall restart &
		MIMESH_LOGI "Device was initted! clear br-port isolate_mode!"

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
	/etc/init.d/tbusd restart &
	/etc/init.d/trafficd restart &
	/etc/init.d/xiaoqiang_sync restart &
	/etc/init.d/messagingagent.sh restart &

	/etc/init.d/miwifi-roam restart &
	/etc/init.d/topomon restart &

	return 0
}

mimesh_init()
{
	#gpio_led l green 600 600 &

	### get whc keys
	#json_load "$params"
	export bsd=1
	export method="$(json_get_value "$1" method)"
	export params="$(json_get_value "$1" params)"
	
	local eth_init=$2
	[ -z "$2" ] && eth_init=0
	export eth_init="$eth_init"

	local para_bsd="`json_get_value \"$params\" \"bsd\"`"
	[ "$para_bsd" = "0" ] && bsd=0
	MIMESH_LOGI " keys:<bsd:$bsd>"
	[ "$bsd" -eq 0 ] && key_list="whc_role ssid_2g mgmt_2g pswd_2g ssid_5g mgmt_5g pswd_5g" || key_list="whc_role whc_ssid whc_pswd whc_mgmt"

	key_list="$key_list bh_ssid bh_mgmt bh_pswd bh_macnum_5g bh_maclist_5g"

	for key in $key_list; do
		#echo $key
		eval "export $key=\"\""
		eval "$key=\"`json_get_value \"$params\" \"$key\"`\""

		[ -z "$key" ] && {
			MIMESH_LOGE " error whc_init, no $key exist"
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

		[ -z "$bh_ssid" ] && bh_ssid_5g="MiMesh_A1B2"
		[ -z "$bh_mgmt" ] && bh_mgmt_5g="psk2+ccmp"
		[ -z "$bh_pswd" ] && bh_mgmt_5g="none"
		[ -z "$bh_macnum_2g" -o "$bh_macnum_2g" -eq 0 ] && bh_maclist_2g=""
		[ -z "$bh_macnum_5g" -o "$bh_macnum_5g" -eq 0 ] && bh_maclist_5g=""
		MIMESH_LOGI " keys:<$whc_role>,<$bsd>,<$ssid_2g>,<$pswd_2g>,<$mgmt_2g>,<$ssid_5g>,<$pswd_5g>,<$mgmt_5g>,<$bh_ssid>,<$bh_pswd>,<$bh_mgmt>"
		MIMESH_LOGI " keys:<$bh_macnum_2g>,<$bh_maclist_2g>,<$bh_macnum_5g>,<$bh_maclist_5g>"

	else
		[ -z "$whc_ssid" ] && whc_ssid="!@Mi-son" || whc_ssid="`printf \"%s\" \"$whc_ssid\" | base64 -d`"
		[ -z "$whc_mgmt" ] && whc_mgmt="mixed-psk"
		[ -z "$whc_pswd" ] && whc_mgmt="none" || whc_pswd="`printf \"%s\" \"$whc_pswd\" | base64 -d`"

		[ -z "$bh_ssid" ] && bh_ssid_5g="MiMesh_A1B2"
		[ -z "$bh_mgmt" ] && bh_mgmt_5g="psk2"
		[ -z "$bh_pswd" ] && bh_mgmt_5g="none"
		[ -z "$bh_macnum_2g" -o "$bh_macnum_2g" -eq 0 ] && bh_maclist_2g=""
		[ -z "$bh_macnum_5g" -o "$bh_macnum_5g" -eq 0 ] && bh_maclist_5g=""
		MIMESH_LOGI " keys:<$whc_role>,<$bsd>,<$whc_ssid>,<$whc_pswd>,<$whc_mgmt>,<$bh_ssid>,<$bh_pswd>,<$bh_mgmt>"
		MIMESH_LOGI " keys:<$bh_macnum_2g>,<$bh_maclist_2g>,<$bh_macnum_5g>,<$bh_maclist_5g>"

	fi

	case "$whc_role" in
		cap|CAP)
			# check if wireless is not default, then recreate it for a safe multi calling
			mimesh_preinit "$whc_role"
			ret=$?
			[ $ret -eq $WIFI_INIT_NOCHANGE ] || {
				__init_cap
				ret=$?
			}

			;;

		re|RE)
			__init_re
			ret=$?
			;;
		*)
			MIMESH_LOGE " invalid role $whc_role"
			message="\" error whc_init, invalid role $whc_role\""
			ret=$ERR_PARAM_INV
			;;
	esac

	[ "$ret" -ne 0 ] && {
		MIMESH_LOGE "    init $whc_role error!"
		#gpio_led l yellow 1000 1000 &
	}

	MIMESH_LOGI " --- "
	return 0
}
