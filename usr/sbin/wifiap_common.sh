#!/bin/sh
# Copyright (C) 2014 Xiaomi


global_ssid=""
global_encryption=""
global_enctype=""
global_password=""
global_channel=""
global_bandwidth=""


# escape char  \ ' " to \\ \' \"
WIFIAP_SCANLIST_FILE="/tmp/.WIFIAP_SCANLIST_FILE"
WIFIAP_PARAMETER_CACHE="/tmp/.WIFIAP_PARAMETER_CACHE"

###################################################################################################
#
#     common process
#
###################################################################################################

wifiap_logger()
{
    echo "wifiap: $1"
    logger -t wifiap "$1"
}

escape_string()
{
    #echo "$1"| sed -e 's/\\/\\\\/g;s/\"/\\\"/g;s/`/\\`/g'
    echo $1
}

#key/value file format 
#key1:value1
#key2:value2
#key3:value3
#
#$1 key/value file name
#$2 key name
wifiap_get_value() 
{  
    awk -F ':' '{if($1~/^'$1'/) print $2}' $2
}


wifiap_parameter_save()
{
    touch $WIFIAP_PARAMETER_CACHE
    echo ssid:$global_ssid >$WIFIAP_PARAMETER_CACHE
    echo encryption:$global_encryption >>$WIFIAP_PARAMETER_CACHE
    echo enctype:$global_enctype >>$WIFIAP_PARAMETER_CACHE
    echo password:$global_password >>$WIFIAP_PARAMETER_CACHE
    echo channel:$global_channel >>$WIFIAP_PARAMETER_CACHE
    echo bandwidth:$global_bandwidth >>$WIFIAP_PARAMETER_CACHE

    return 0;
}


wifiap_parameter_restore()
{
    [ -f $WIFIAP_PARAMETER_CACHE ] || return 1

    global_ssid=`wifiap_get_value       ssid       $WIFIAP_PARAMETER_CACHE`
    global_encryption=`wifiap_get_value encryption $WIFIAP_PARAMETER_CACHE`
    global_enctype=`wifiap_get_value    enctype    $WIFIAP_PARAMETER_CACHE`
    global_password=`wifiap_get_value   password   $WIFIAP_PARAMETER_CACHE`
    global_channel=`wifiap_get_value    channel    $WIFIAP_PARAMETER_CACHE`
    global_bandwidth=`wifiap_get_value  bandwidth  $WIFIAP_PARAMETER_CACHE`

    return 0;
}

wifiap_parameter_check()
{
    password_len=`expr length $global_password`

    [ $global_encryption == "psk" -a $password_len -lt 8 ] && return 1;
    [ $global_encryption == "psk2"-a $password_len -lt 8 ] && return 1;
    [ $global_encryption == "mixed-psk" ] && [ $password_len -lt 8 -o $password_len -gt 63 ] && return 1;
    [ $global_encryption == "wep-open" ] &&  [ $password_len != 5 -a $password_len != 13  ] && return 1;

    [ $global_hidden != "1" -a $global_hidden != "0" ] && return 1;

    return 0
}

wifiap_parameter_print()
{
    echo "root AP:"
    echo "    ssid      : $global_ssid"
    echo "    password  : $global_password"
    echo "    channel   : $global_channel"
    echo "    encryption: $global_encryption"
    echo "    enctype   : $global_enctype"
    echo "    bandwidth : $global_bandwidth"

    return 0
}

#AuthMode: OPEN SHARED AUTOWEP WPA WPAPSK WPANONE WPANONE WPA2 WPA2PSK WPA1WPA2 WPA1PSKWPA2PSK WAI-CERT WAI-PSK UNKNOW
#GetEncryptType:  NONE WEP TKIP AES TKIPAES SMS4 UNKNOW

wifiap_enctype_translate()
{
    if   [ "$1" == "TKIPAES" ] 
    then
        echo "mixed-psk"
    elif [ "$1" == "AES" ] 
    then
        echo "wpa2-psk"
    elif [ "$1" ==  "TKIP" ]
    then
        echo "wpa-psk"
    elif [ "$1" == "WEP" ]
    then
        echo "wep"
    else
        echo "none"
    fi

    return 0
}

wifiap_lan_restart()
{
    wifiap_logger "try restart lan."
    for i in `seq 1 10`
    do
       /usr/sbin/phyhelper restart
       [ $? = '0' ] && return 0;

       wifiap_logger "restart lan fail, try again in $i seconds."
       sleep $i
    done
    
    return 1;
}

wifiap_service_restart()
{
    #R1D CANT RESTART NETWORK
    #/etc/init.d/network restart  1>/dev/null 2>/dev/null

    /etc/init.d/trafficd restart 1>/dev/null 2>/dev/null 
    /etc/init.d/dnsmasq restart 1>/dev/null 2>/dev/null
    /etc/init.d/xqbc restart 1>/dev/null 2>/dev/null
    /etc/init.d/miqos restart 1>/dev/null 2>/dev/null

    /etc/init.d/plugin_start_script.sh stop
    /etc/init.d/plugin_start_script.sh start

    return 0
}

router_config_backup()
{
    local config_dir="/etc/config/"
    local config_backup_dir="/etc/config/"
    local backup_suffix=".mode.router"
     
    wifiap_logger "router mode configure $1 backup." 

    [ -z $1 ] && (echo "$0 arg 1 NULL.";return 1;) 
    
    local source_file=$config_dir"/"$1
    local dest_file=$config_backup_dir"/""."$1"$backup_suffix"

    [ -f $source_file ] || { wifiap_logger "backup file $source_file not exist.";return 1; }

    rm $dest_file 1>/dev/null 2>/dev/null
    cp $source_file $dest_file 1>/dev/null 2>/dev/null

    return 0
}

router_config_recover()
{
    local config_dir="/etc/config/"
    local config_backup_dir="/etc/config/"
    local backup_suffix=".mode.router"

    wifiap_logger "router mode configure $1 recover."

    [ -z $1 ] && { echo "$0 arg 1 NULL.";return 1; }
    
    local dest_file=$config_dir"/"$1
    local source_file=$config_backup_dir"/""."$1"$backup_suffix"

    [ -f $source_file ] || { wifiap_logger "recover config $source_file not exist.";return 1; }
    
    mv $source_file $dest_file
    
    return 0
}

wifiap_config_backup()
{
    #network backup by dhcp_client.sh
    #router_config_backup "network"
    router_config_backup "wireless"  1>/dev/null 2>/dev/null
    router_config_backup "dhcp"  1>/dev/null 2>/dev/null

    return 0
}

wifiap_config_recover()
{
    router_config_recover "network" 1>/dev/null 2>/dev/null
    router_config_recover "wireless" 1>/dev/null 2>/dev/null
    router_config_recover "dhcp" 1>/dev/null 2>/dev/null

    return 0
}

wifiap_fail_process()
{
    wifiap_config_recover 1>/dev/null 2>/dev/null
    wifiap_service_restart 1>/dev/null 2>/dev/null

    wifiap_logger "wifiap setup fail process."

    return 0
}

wifiap_wifi_open()
{
    local WIFI2G=`uci get misc.wireless.if_2G`
    local wifi_on=`uci get wireless.$WIFI2G.disabled`

    [ $wifi_on != 0 ] && return

    uci set wireless.$WIFI2G.disabled=0
    uci commit wireless
    /sbin/wifi enable $WIFI2G 1>/dev/null 2>/dev/null
}

wifiap_dhcp_start()
{
    wifiap_logger "try get ip."
    for i in `seq 1 6`
    do
       /usr/sbin/dhcp_apclient.sh start br-lan
       [ $? = '0' ] && return 0;
       wifiap_logger "start dhcp fail, try again in 10 seconds."
       sleep 10
    done

    wifiap_logger "dhcp fail."
    return 1;
}

wifiap_scan_output()
{
    [ ! -f $WIFIAP_SCANLIST_FILE ] && return 1

    #eg:channel ssid       mac               security signal  wmode   extch nt xm wps
    #   1       <MIOffice> 94:b4:0f:8d:a3:40 WPA2/AES 7       11b/g/n NONE  In NO
    #channel   substr($0, 1, 3)
    #ssid      substr($0, 5, 32)
    #bssid     substr($0, 38, 19)
    #security  substr($0, 58, 23)
    #signal    substr($0, 81, 3)
    #wmode     substr($0, 87, 7)
    #extch     substr($0, 95, 6)
    #NT        substr($0, 102, 2)
    #XM        substr($0, 105, 5)
    #WPS       substr($0, 111, 3)
    #DPID       substr($0, 115, 4)

    echo "{"
    echo "root_ap_list:["
    cat $WIFIAP_SCANLIST_FILE | awk '{
        ssid=substr($0, 5, 32); 
        gsub(/^ *<|> *$/,"", ssid);
        bssid=substr($0, 38, 19); 
        gsub(/^ *| *$/,"", bssid);
        channel=substr($0, 1, 3); gsub(/^ *| *$/,"", channel);
        gsub(/^ *| *$/,"", channel);
        security=substr($0, 58, 23); 
        gsub(/^ *| *$/,"", security);
        signal=substr($0, 81, 3); 
        gsub(/^ *| *$/,"", signal);
        wmode=substr($0, 87, 7); 
        gsub(/^ *| *$/,"", wmode);
        extch=substr($0, 95, 6); 
        gsub(/^ *| *$/,"", extch);
        NT=substr($0, 102, 2); 
        gsub(/^ *| *$/,"", NT);
        XM=substr($0, 105, 5); 
        gsub(/^ *| *$/,"", XM);
        WPS=substr($0, 111, 3); 
        gsub(/^ *| *$/,"", WPS);
        DPID=substr($0, 115, 4); 
        gsub(/^ *| *$/,"", DPID);

        print "    {";
        print "        SSID:"ssid",";
        print "        BSSID:"bssid",";
        print "        channel:"channel",";        
        print "        Security:"security",";
        print "        Signal:"signal",";
        print "        W-mode:"wmode",";
        print "        ExtCH:"extch",";
        print "        NT:"NT",";
        print "        XM:"XM",";
        print "        WPS:"WPS",";
        print "        DPID:"DPID"";
        print "    }";
        }' 
    echo "]"
    echo "}"
}


