#!/bin/sh

RET()
{
    echo -n "$1"
}

base64_enc()
{
    ## encode and unfold mutiple line
    local str="`echo -n "$1" | base64 | sed 's/ //g'`"
    RET "$str" | awk -v RS="" '{gsub("\n","");print}'
}

parse_width_from_mode()
{
	width=$(echo $1 | grep 160)
	if [ ! -z $width ]; then
		width="160MHz"
	else
		width=$(echo $1 | grep 80)
		if [ ! -z $width ]; then
			width="80MHz"
		else
			width=$(echo $1 | grep 40)
			if [ ! -z $width ]; then
				width="40MHz"
			else
				width="20MHz"
			fi
		fi
	fi
	
	RET "$width"
}

parse_phymode_from_mode()
{
	phymode=$(echo $1 | grep HE)
	if [ ! -z $phymode ]; then
		phymode="he"
	else
		phymode=$(echo $1 | grep AC)
		if [ ! -z $phymode ]; then
			phymode="vht"
		else
			phymode=$(echo $1 | grep NG)
			if [ ! -z $phymode ]; then
				phymode="ht"
			else
				phymode=$(echo $1 | grep NA)
				if [ ! -z $phymode ]; then
					phymode="ht"
				else
					phymode="basic"
				fi
			fi
		fi
	fi
	
	RET "$phymode"
}

whc_mode="$1"

ap_ifname_5g=$(uci -q get misc.wireless.ifname_5G)
ap_ifname_2g=$(uci -q get misc.wireless.ifname_2G)
iface_2g=$(uci show wireless | grep "ifname=\'$ap_ifname_2g\'" | awk -F"." '{print $2}')
iface_5g=$(uci show wireless | grep "ifname=\'$ap_ifname_5g\'" | awk -F"." '{print $2}')

lan_mac=`ifconfig br-lan |grep HWaddr | awk '{print $5}'`
bssid_2g=`ifconfig "$ap_ifname_2g" |grep HWaddr | awk '{print $5}'`
bssid_5g=`ifconfig  "$ap_ifname_5g" |grep HWaddr | awk '{print $5}'`

#get 2g ssid
ssid_2g=$(uci -q get wireless.$iface_2g.ssid)

#get 2g nss
nss_2g=`iwpriv wl1 get_nss | awk -F '[:]' '{print $NF}' | sed 's/[ \t]*$//g'`

#get 2g channel
channel_2g="`iwlist wl1 channel | grep -Eo "\(Channel.*\)" | grep -Eo "[1-9]+"`"

#get 2g width and phy mode
mode="`iwpriv wl1 get_mode | awk -F '[:]' '{print $NF}'`"
width_2g=$(parse_width_from_mode $mode)
phymode_2g=$(parse_phymode_from_mode $mode)

#get 5g ssid
ssid_5g=$(uci -q get wireless.$iface_5g.ssid)

#get 5g nss
nss_5g=`iwpriv wl0 get_nss | awk -F '[:]' '{print $NF}' | sed 's/[ \t]*$//g'`

#get 5g channel
channel_5g="`iwlist wl0 channel | grep -Eo "\(Channel.*\)" | grep -Eo "[0-9]+"`"

#get 5g width and phy mode
mode="`iwpriv wl0 get_mode | awk -F '[:]' '{print $NF}'`"
width_5g=$(parse_width_from_mode $mode)
phymode_5g=$(parse_phymode_from_mode $mode)

#get link type
link_type=$(topomon_action.sh current_status bh_type)

#get 5g backhaul 
backhaul_ap_ifname_5g=$(uci -q get misc.backhauls.backhaul_5g_ap_iface)
backhaul_ap_bssid_5g=`iwconfig "$backhaul_ap_ifname_5g" | grep "Access Point" | awk '{print $6}'`

#get SNR //to do, get from driver
snr=0
uplink_mac=""
eth_link_rate=""

if [ "$whc_mode" == "CAP" ]; then
	uplink_mac=""
	snr=0
	eth_link_rate=""
	link_type="CAP"
elif [ "$link_type" = "wireless" ]; then
	backhaul_sta_ifname_5g=$(uci -q get misc.backhauls.backhaul_5g_sta_iface)
	uplink_mac=`iwconfig "$backhaul_sta_ifname_5g" | grep "Access Point" | awk '{print $6}'`
elif [ "$link_type" = "wired" ]; then
	eth_link_rate=$(topomon_action.sh current_status eth_link_rate)
	uplink_mac=$(topomon_action.sh current_status uplink_mac)
else
	echo "invalid link_type $link_type"
fi

msg="{\
\"lan_mac\":\"$lan_mac\",\"bssid_2g\":\"$bssid_2g\",\"ssid_2g\":\"$(base64_enc "$ssid_2g")\",\"width_2g\":\"$width_2g\",\"channel_2g\":$channel_2g,\"nss_2g\":$nss_2g,\"phymode_2g\":\"$phymode_2g\",\
\"bssid_5g\":\"$bssid_5g\",\"ssid_5g\":\"$(base64_enc "$ssid_5g")\",\"width_5g\":\"$width_5g\",\"channel_5g\":$channel_5g,\"nss_5g\":$nss_5g,\"phymode_5g\":\"$phymode_5g\",\"link_type\":\"$link_type\",\
\"backhaul_ap_bssid_5g\":\"$backhaul_ap_bssid_5g\",\"uplink_mac\":\"$uplink_mac\",\"snr\":$snr,\"eth_link_rate\":\"$eth_link_rate\"}"

echo "$msg"
