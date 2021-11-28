#!/bin/sh

# This file extract xqwhc info from qca son hyd

. /lib/xqwhc/xqwhc_public.sh
. /lib/xqwhc/network_lal.sh
. /lib/xqwhc/xqwhc_metric.sh

export ERR_HYT=50
export ERR_HYT_INFO=51
export ERR_NODE_NOT_MATCH=52
export ERR_NO_BACKHAUL=53
export ERR_ROLE_NOT_CAP=54
export ERR_ROLE_NOT_RE=55

export ERR_NOT_CONNECTTED=59

export ERR_METRIC_NOT_LINK=$METRIC_FAIL
export ERR_METRIC_POOR=$METRIC_POOR
export ERR_METRIC_GOOD=$METRIC_GOOD

# bit mapping for backhauls represent
export BACKHAUL_BMP_2g=0
export BACKHAUL_BMP_5g=1
export BACKHAUL_BMP_resv=2
export BACKHAUL_BMP_eth=3
export BACKHAUL_QA_BMP_GOOD=1
export BACKHAUL_QA_BMP_POOR=0

export BH_2G_METRIC_WEIGHT=0       # for qca son, experience takes most weight on 5G, so in ONLY 2G case. show as POOR metric

### miwifi:  ConnectionMap represent bit of backhaul connect to hyd
# for td s2 in CAP, bit5~bit0: eth4 eth3 eth2 5g_bh 2g 5g on AX3600
# for td s2 in CAP, bit5~bit0: eth3 eth2 eth1 5g_bh 2g 5g on RM1800
# for td s2 in RE, bit7~bit0: eth1 eth4 eth3 eth2 5g_bh 5g_sta 2g 5g on AX3600
# for td s2 in RE, bit7~bit0: eth4 eth3 eth2 eth1 5g_bh 5g_sta 2g 5g on RM1800
case "$BH_METHOD" in
    $USE_DUAL_BAND_BH)
        CAP_5G_BH=$((1<<0))
        CAP_2G_BH=$((1<<1))
        CAP_ETH_BH=$(( (1<<2) + (1<<3) + (1<<4) ))
        RE_5G_BH=$((1<<2))
        RE_2G_BH=$((1<<3))
        RE_ETH_BH=$(( (1<<4) + (1<<5) + (1<<6) + (1<<7) ))
    ;;
    $USE_ONLY_5G_BH)
        CAP_5G_BH=$((1<<0))
        CAP_2G_BH=$((1<<1))
        CAP_ETH_BH=$(( (1<<2) + (1<<3) + (1<<4) ))
        RE_5G_BH=$((1<<2))
        RE_2G_BH=0 # no use if only 5G backhaul
        RE_ETH_BH=$(( (1<<3) + (1<<4) + (1<<5) + (1<<6) ))
    ;;
    $USE_ONLY_5G_IND_VAP_BH)
        CAP_5G_BH=$((1<<2))
        CAP_2G_BH=$((1<<1))
        CAP_ETH_BH=$(( (1<<3) + (1<<4) + (1<<5) ))
        RE_5G_BH=$((1<<2))
        RE_2G_BH=0 # no use if only 5G backhaul
        RE_ETH_BH=$(( (1<<4) + (1<<5) + (1<<6) + (1<<7) ))
    ;;
    *) #$USE_DUAL_BAND_IND_VAP_BH
        CAP_5G_BH=$((1<<2))
        CAP_2G_BH=$((1<<3))
        CAP_ETH_BH=$(( (1<<4) + (1<<5) + (1<<6) ))
        RE_5G_BH=$((1<<2))
        RE_2G_BH=$((1<<3))
        RE_ETH_BH=$(( (1<<4) + (1<<5) + (1<<6) + (1<<7) ))
    ;;
esac

####BEGIN enumeration ConnectionMap in hyd topology service
## based on ess cfg eth1/eth2/eth3/eth4 on RM1800/AX3600
## backhauls     :  CAP view            RE view
# 5+2            :   0x3                  0xc
# 5g             :   0x1                  0x4
# 2g             :   0x2                  0x8
# if "$USE_ONLY_5G_BH" = "1", below
# 5g             :   0x1                  0x4
# if "$USE_ONLY_5G_IND_VAP_BH" = "1", below
# 5g             :   0x4                  0x4


## special table for eth backhaul, as multi eth iface on lan, so multi bits represent the eth backhaul
# CAP     RE      CAP_cmap         RE_cmap   RE_cmap(only 5G bh)
# eth2   eth2       0x4             0x10        0x8
# eth2   eth3       0x4             0x20        0x10
# eth2   eth4       0x4             0x40        0x20
# eth2   eth1       0x4             0x80        0x40
# eth3   eth2       0x8             0x10        0x8
# eth3   eth3       0x8             0x20        0x10
# eth3   eth4       0x8             0x40        0x20
# eth3   eth1       0x8             0x80        0x40
# eth4   eth2       0x10            0x10        0x8
# eth4   eth3       0x10            0x20        0x10
# eth4   eth4       0x10            0x40        0x20
# eth4   eth1       0x10            0x80        0x40
####END enumeration ConnectionMap in hyd topology service


### miwifi: backhaul quality threshold by raw_phy_datarate
# wlan pc s 2 / pc s 5
# repacd.WiFiLink.RateThresholdMin5GInPercent RateThresholdMax5GInPercent
MAX_RATIO=`uci -q get repacd.WiFiLink.RateThresholdMax5GInPercent`
[ -z "$MAX_RATIO" ] && MAX_RATIO=70
MIN_RATIO=`uci -q get repacd.WiFiLink.RateThresholdMin5GInPercent`
[ -z "$MIN_RATIO" ] && MIN_RATIO=40

# get wifi max rate, depends on band_width, default, will get every time
MAX_RATE_2G=286
MAX_RATE_5G=1201

BH_2G_DR_GOOD=$(($MAX_RATE_2G * ${MAX_RATIO} / 100))
BH_2G_DR_MIN=$(($MAX_RATE_2G * ${MIN_RATIO} / 100))
BH_5G_DR_GOOD=$(($MAX_RATE_5G * ${MAX_RATIO} / 100))
BH_5G_DR_MIN=$(($MAX_RATE_5G * ${MIN_RATIO} / 100))

tmpf="/tmp/hyt.dat"

# telnet port is differ in private and guest network
PORT_PRIV="7777"
PORT_GUEST="8888"
HYT_PRIV="telnet 127.0.0.1 $PORT_PRIV"
HYT_GUEST="telnet 127.0.0.1 $PORT_GUEST"

DELAY=2     # notice, sleep maybe  on different hyt cmd.

# launch hyt cmd on local dev
__hyt_info_local()
{
    local hyt_cmd="$1"

    if [ "$XQWHC_DEBUG" = "1" ]; then
        info="`(echo "$hyt_cmd"; sleep $DELAY; echo q ) | $HYT_PRIV 2>/dev/null | tee "$tmpf"`"
        WHC_TRACE " hyt_info $hyt_cmd = $info "
    else
        info="`(echo "$hyt_cmd"; sleep $DELAY; echo q ) | $HYT_PRIV 2>/dev/null`"
    fi
    [ -n "$info" ]
}

# hyt td s2, -- ME: part
# $1: td s2 info
# output: -- ME part
__hyt_get_td_me()
{
    local info="$1"
    echo "$info" | sed -n '/^-- ME:/,/^-- DB/ p' | sed '$s/-- DB.*//g'

    return 0
}

# get td s2 DB enctry count
# $1: db_all
# out: count
__hyt_get_td_db_cnt()
{
    local db_all="$1" 
    echo "$db_all" | grep -E "^-- DB (.*)" | grep -oE "[0-9]+"
    return 0
}

# hyt get all remote dbs info
# $1: td s2 info
# output: db_all
__hyt_get_td_db_all()
{
    local info="$1"
    echo "$info" | sed -n '/^\-\- DB ([0-9]\+ entries):/,$ {p}'
    return 0
}

# hyt: get cap addr only from RE's perspective with pattern = "**Network relaying device**"
# $1: input  db_all
# output: 1905 cap_addr
__re_hyt_get_td_cap_addr()
{
    local cap_db_patt="**Network relaying device**"
    local db_all="$1"
    echo "$db_all" | grep -w "$cap_db_patt" | grep -E -o "..:..:..:..:..:.."
    return 0
}

# hyt get single remote db info by 1905 addr
# $1: db_all info
# $2: remote db 1905 dev addr
# output db info, from : '1905.1 device:' to next '1905.1 device:' or EOF
__hyt_get_td_db_single_byaddr()
{
    local pattern="QCA IEEE 1905.1 device:"
    local db_all="$1"
    local db_addr="$2"
    
    local db=`echo "$db_all" | sed -n "/QCA IEEE 1905.1 device: $db_addr/,/QCA IEEE 1905.1 device/ p"`
    # delete nextheader of otherdb if exist
    echo "$db" | sed '$s/.*QCA IEEE 1905.1 device.*//g'

    return 0
}

# hyt get single remote db info by db entry index
# $1: db_all info
# $2: db index
# output db info, from : '#i' to next '#i+1' or EOF
__hyt_get_td_db_single_byidx()
{
    local db_all="$1"
    local idx="$2"

    local db="`echo "$db_all" | sed -n '/#'${idx}': QCA IEEE 1905.1 device/,/#'$((idx + 1))': QCA IEEE 1905.1 device/ p'`" 

    # delete nextheader of otherdb if exist
    echo "$db" | sed '$s/.*QCA IEEE 1905.1 device.*//g'
    
    return 0
}

# extract db addr from db info
# $1: db info
# out: 1905 addr
__hyt_get_td_db_addr()
{
    local db="$1"
    echo "$db" | grep -w ".*QCA IEEE 1905.1 device:.*address" | grep -E -o "..:..:..:..:..:.."
    return 0
}

# extract db ip addr from db info
# $1: db info
# out: 1905 ip addr
__hyt_get_td_db_ip()
{
    local db="$1"
    echo "$db" | grep -w ".*QCA IEEE 1905.1 device:.*address" | grep -E -o "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"
    return 0
}


# hyt get self & db ConnectionMap val
# $1: single db info
# outout: ConnectionMap value
__hyt_get_td_db_connmap()
{
    local db="$1"
    echo "$db" | awk -F':' '/ConnectionMap/ {print $2}'
    return 0
}

# hyt get self & db ConnectionMap val
# $1: single db info
# outout: ConnectionMap value
__hyt_get_td_db_relation()
{
    local db="$1"
    echo "$db" | awk -F': ' '/Relation/ {print $2}' 
    return 0
}

# get db/me upstream deivce
# $1: db / me  infos
# out: upstream dev addr
__hyt_get_td_db_upstream()
{
    local db="$1"
    echo "$db" | awk -F': ' '/Upstream Device/ {print $2}' 
    return 0
}


# check relation is Direct to addr
__if_relation_direct()
{
    [ "Direct Neighbor" = "$1" ]
}

# check if upstream valid
__if_upstream_valid()
{
    echo "$1" | grep -E -oq "..:..:..:..:..:.." && [ "00:00:00:00:00:00" != "$1" ]
}


# generic -- get wifi sta iface snr level, called by RE has wifi sta iface
# $1 input sta iface
# $2 output snr level: poor mid good
#        snr extract from iwconfig after iface assoced, handle same as repacd-wifimon measuring
__re_get_wifi_bh_qa()
{
    local iface="$1"
    local __freq=""
    local option_near="RSSIThresholdNear"
    local option_far="RSSIThresholdFar"
    local rssi_thr_near="`uci -q get repacd.WiFiLink.$option_near`"
    local rssi_thr_far="`uci -q get repacd.WiFiLink.$option_near`"

    local __state="`iwconfig $iface 2>&1`"

    # enhanced to make sure sta vap is assoced
    echo "$__state" | grep "Access Point" | grep -E -oq "..:..:..:..:..:.." || {
        return 11
    }

    __snr=`echo "$__state" | grep -o "Signal level=[-0-9]* dBm" | grep -o "[-0-9]*"`

    nlal_get_wiface_freq "$iface" __freq
    [ -n "$__freq" ] && {
        new_option_near="${option_near}_${__freq/g/G}"
        new_option_far="${option_far}_${__freq/g/G}"
    }
    [ -n "`uci -q get repacd.WiFiLink.$new_option_near`" ] && rssi_thr_near="`uci -q get repacd.WiFiLink.$new_option_near`"
    [ -n "`uci -q get repacd.WiFiLink.$new_option_far`" ] && rssi_thr_far="`uci -q get repacd.WiFiLink.$new_option_far`"

    eval "$2=''"
    if [ "$__snr" -ge "$rssi_thr_near" ]; then
        WHC_LOGD " get_sta $iface snr= $__snr > $rssi_thr_near"
        eval "$2=good"
    elif [ "$__snr" -ge "$rssi_thr_far" ]; then
        WHC_LOGD " get_sta $iface snr= $__snr > $rssi_thr_far"
        eval "$2=mid"
    else
        WHC_LOGI " poor get_sta $iface snr= $__snr < $rssi_thr_far"
        eval "$2=poor"
    fi

    return 0
}


# get db's remote connections by wifi type in db info block, ONLY called on CAP
# $1: db info
# $2: type 2g/5g
# output: sta addr
__cap_get_td_db_wifi_sta()
{
    local db="$1"
    local type="${2/g/}"

    local patt1="Remote connections (Directly connected to self)"
    local patt2="Remote connections (Not directly connected to self)"
    local rcons="`echo "$db" | sed -n "/$patt1/,/$patt2/ p"`"
    echo "$rcons" | grep -w "WLAN${type}G" | awk '{print $3}'
    return 0
}


# get remote path character info of wlan bh
#$1: input pc info block
#$2: sta addr
#output: qa  poor/mid/good  by "--> raw phy rate"
__hyt_pc_get_wifi_bh_qa()
{
    local pcinfo="$1"
    local addr="$2"

    return 0
}

# generic -- get sta max rate, called by CAP
# $1 input wlan type  2/5
# $2 input sta addr
# $3 output max rate
__cap_get_sta_max_rate()
{
    local type="$1"
    local addr="$2"
    local patt="MAXRATE(DOT11)"
    local vap_if column

    if [ "$type" = "2" ]; then
        [ "$BH_METHOD" -eq "$USE_DUAL_BAND_IND_VAP_BH" ] && vap_if="`uci get misc.backhauls.backhaul_2g_ap_iface`" || vap_if="wl1"
    else
        if [ "$BH_METHOD" -eq "$USE_ONLY_5G_IND_VAP_BH" -o "$BH_METHOD" -eq "$USE_DUAL_BAND_IND_VAP_BH" ]; then
            vap_if="`uci get misc.backhauls.backhaul_5g_ap_iface`"
        else
            vap_if="wl0"
        fi
    fi
    local info="`wlanconfig $vap_if list | sed -n '1p'`"
    local column_num="`wlanconfig $vap_if list | sed -n '1p' | awk -F ' ' '{print NF}'`"

    for i in `seq 1 $column_num`
    do
        column_name="`echo "$info" | awk -v a=$i '{print $a}'`"
        [ "$column_name" = "$patt" ] && {
            column=$i
            break
        }
    done
    [ -z "$column" ] && column=17 # default 17 on RM1800/AX3600
    local maxrate="`wlanconfig $vap_if list | grep -i "$addr" | awk -v c=$column -F ' ' '{print $c}'`"
    [ -n "$maxrate" ] && maxrate=$(($maxrate / 1000))
    eval "$3=$maxrate"
}

# generic -- get wifi backhaul qa, called by CAP
# $1 input db info
# $2 input wlan type  2/5/P/E
# $3 output level: poor mid good
#        snr extract from pc s 2/5 --> raw phy rate = 86
__cap_get_wifi_bh_qa()
{
    local db="$1"
    local type="$2"
    local qa=""
    local info=""

    local raddr="$(__cap_get_td_db_wifi_sta "$db" $type)"
    local patt1="Number of links"
    local patt2="Remote STA medium information"
    local patt="\-\-> raw phy rate"
    __hyt_info_local "pc s $type"


# sample link info from hyt pc s 2: 
#        Number of links = 1
#                Link #0: DA = 5A:64:2B:B5:7E:DD --> Available/Full TCP Link capacity = 0/87 Mbps, Available/Full UDP Link capacity = 0/97 Mbps
#                        RAW link data:
#                                 --> raw phy rate = 115
#                                 --> average aggregation = 96
#                                 --> PHY Error Rate = 12
#                                 --> Last PER = 0
#                                 --> MSDU Size = 1300
#                                 --> Derived raw TCP Estimated Throughput = 87 Mbps
#                                 --> Derived raw UDP Estimated Throughput = 97 Mbps


    local link_all="`echo "$info" | sed -n "/$patt1/,/$patt2/ p"`"
    local link="`echo "$link_all" | grep -E "Link.*DA = $addr" -A 4`"
    local rawrate="`echo "$link" | grep -w "$patt" | awk '{print $6}'`"
    [ -z "$rawrate" ] && rawrate=0

    # check rawrate level
    #local t1=BH_${type}G_DR_GOOD
    #local t2=BH_${type}G_DR_MIN
    #local thresgood=`eval echo '$'"$t1"`
    #local thresmin=`eval echo '$'"$t2"`
    local max_rate=""
    __cap_get_sta_max_rate $type $raddr max_rate
    [ -z "$max_rate" ] && max_rate="`eval echo '$'{MAX_RATE_"${type}"G}`"
    local thresgood="$(($max_rate * ${MAX_RATIO} / 100))"
    local thresmin="$(($max_rate * ${MIN_RATIO} / 100))"
    if [ "$rawrate" -ge "$thresgood" ]; then
        qa="good"
    elif [ "$rawrate" -ge "$thresmin" ]; then
        qa="mid"
    else
        qa="poor"
    fi

    WHC_LOGD "  RE $dbmac, wlan bh ${type}G, rate=$rawrate,$thresgood,$thresmin, qa=$qa"
    eval "$3=$qa"
    return 0
}

# translate connmap to backhaul in CAP's perspective
# for CAP
# $1: connmap value
# $2: output bhs
# $3: output bh_qas
__cap_hyt_connmap2backhauls()
{
    local M2BH_map="$1"
    local M2BH_qa=""

    if [ $((M2BH_map & CAP_ETH_BH)) -gt 0 ]; then
        eval "append $2 eth"
        eval "append $3 good"
    fi

    if [ $((M2BH_map & CAP_2G_BH)) -gt 0 ]; then
        __cap_get_wifi_bh_qa "$db" 2 M2BH_qa
        eval "append $2 2g"
        eval "append $3 $M2BH_qa"
    fi
        
    if [ $((M2BH_map & CAP_5G_BH)) -gt 0 ]; then
        __cap_get_wifi_bh_qa "$db" 5 M2BH_qa
        eval "append $2 5g"
        eval "append $3 $M2BH_qa"
    fi

    [ -z "$M2BH_qa" ] && WHC_LOGI " cap_hyt_connmap is $M2BH_map, no backhauls found! "
    [ -n "$M2BH_qa" ]
}

# translate connmap to backhaul in CAP's perspective
# for CAP
# $1: connmap value
# $2: output bhs
# $3: output bh_qas
__re_hyt_connmap2backhauls()
{
    local M2BH__map="$1"
    local M2BH__qa=""
    local M2BH__iface
    local ret=0

    if [ $((M2BH__map & RE_ETH_BH)) -gt 0 ]; then
        eval "append $2 eth"
        eval "append $3 good"
    fi

    if [ $((M2BH__map & RE_2G_BH)) -gt 0 ]; then
        # calc backhaul qa
        nlal_get_sta_iface "2g" M2BH__iface
        __re_get_wifi_bh_qa $M2BH__iface M2BH__qa && {
            eval "append $2 2g"
            eval "append $3 $M2BH__qa"
        } || {
            WHC_LOGI " ***warning, sta $M2BH__iface list in hyt, but NOT assoc actually!"
        }
    fi

    if [ $((M2BH__map & RE_5G_BH)) -gt 0 ]; then
        nlal_get_sta_iface "5g" M2BH__iface
        __re_get_wifi_bh_qa $M2BH__iface M2BH__qa && {
            eval "append $2 5g"
            eval "append $3 $M2BH__qa"
        } || {
            WHC_LOGI " ***warning, sta $M2BH__iface list in hyt, but NOT assoc actually!"
        }
    fi

    [ -n "eval echo '$'$2" ]
    return $ret
}


# get path characterization for backhaul quality
# $1: pc cmd :  2g/5g,  now only support wifi iface
# $2: remote db addr
__hyt_pc_info()
{
    __hyt_info_local "pc s 2"

   return 0 
}


__backhaul2bmp()
{
    local raw_bhs="$1"
    local __bmp=0
    #use reserved instead of ori plc
    for bb in 2g 5g eth; do
        list_contains raw_bhs $bb && {
            local bit=`eval echo '$'BACKHAUL_BMP_$bb`
            __bmp=$((__bmp | (1 << $bit) ))
        }
    done

    eval "$2=$__bmp"
    [ "$__bmp" -gt 0 ]
}

__backhaul_qa2bmp()
{
    local raw_bhs_qa="$1"
    local bh_bmp="$2"


    # process qa bitmap
    # eg: raw_qa="good poor good", bmp=7; output=5 
    # eg: raw_qa="good", bmp=8; output=8
    __qa_bmp=0
    qai=1
    for i in `seq 0 1 3`; do
        if [ $((bh_bmp & (1 << i))) -eq 0 ]; then
            continue
        fi

        local qa="`echo "$raw_bhs_qa" | awk '{print $jj}' jj="$qai"`"
#echo "@@@@qa=[$qa], qai=$qai, i=$i"
        if [ "$qa" = "good" -o "$qa" = "mid" ]; then
            __qa_bmp=$((__qa_bmp + (1 << i)))
            qai=$((qai+1))
        elif [ "$qa" = "poor" ]; then
            qai=$((qai+1))
        else
            break;
        fi
    done

    eval $3=$__qa_bmp
}

# RE's perspective to get active bakchauls to upstream, ONLY called on RE
# $1: output upstream macaddr
# $2: output upstream ipaddr
# $3: output hyt active backhauls
# $4: output QA of active backhauls, order according to $1
__re_hyt_get_backhauls()
{
    #local db_all=$(__hyt_get_td_db_all "$info")
    local upre=""
    local upre_ip=""
    local connmap=""
    local mt_buff=""
    local ret=0

    # first find cap addr & cap_db, to confirm relation between self and cap
    #local cap_addr="$(__re_hyt_get_td_cap_addr "$db_all")"

    # if RE connect into son, then a cap_addr MUST exist, so use it to check RE connect
    [ -z "$cap_addr" ] && {
        mt_buff="result:fail"
        xqwhc_metric_write "`echo -e "$mt_buff"`"
        WHC_LOGI " re get link metric, fail of NO cap_addr"
        return $ERR_NOT_CONNECTTED
    }

    local db_cap="$(__hyt_get_td_db_single_byaddr "$db_all" "$cap_addr")"
    local relation=$(__hyt_get_td_db_relation "$db_cap")
    if __if_relation_direct "$relation" ; then
        # direct to cap
        WHC_LOGD " RE self direct connect to CAP!"
        upre="$cap_addr"
        upre_ip="$(__hyt_get_td_db_ip "$db_cap")" 
        connmap="$(__hyt_get_td_db_connmap "$db_cap")"
        
        # get backhaul quality
        # for eth, qas always be good
        # for wifi, check iwconfig sta_iface Signal level
    else
        # for distant neighber
        # 1. get upstram
        # 2. for eth bh, upstream is NONE. 
        local me="$(__hyt_get_td_me "$info")"
        local upstream="$(__hyt_get_td_db_upstream "$me")"

        if __if_upstream_valid "$upstream"; then
            WHC_LOGD " RE self distant connect to RE $upstream !"
            local db_up="$(__hyt_get_td_db_single_byaddr "$db_all" "$upstream")"
            upre_ip="$(__hyt_get_td_db_ip "$db_up")"
            connmap="$(__hyt_get_td_db_connmap "$db_up")"
            # if upstream is valid, then we can extract db info by addr, get bhs by connection map

        else
            # if upstream is invalid, simply treated as eth backhaul to RE node
            #  traversal db_all by idx to found a remote RE db with relation is not wifi
            local db_cnt="$(__hyt_get_td_db_cnt "$db_all")"
            local db=""
            local addr=""

            WHC_LOGI " RE self distant connect to RE? find upstream dev!"
            ############### CAUTION here:
            # to find right upstream, relation= Direct && (connmap&RE_ETH_BH)
            for ii in `seq 1 $db_cnt`; do
                db="$(__hyt_get_td_db_single_byidx "$db_all" "$ii")"
                addr="$(__hyt_get_td_db_addr "$db")"
                relation="$(__hyt_get_td_db_relation "$db")"
                connmap="$(__hyt_get_td_db_connmap "$db")"
                __if_relation_direct "$relation" && {
                    [ $((connmap & RE_ETH_BH)) -gt 0 ] && {
                        upstream="$addr"
                        upre_ip="$(__hyt_get_td_db_ip "$db")"
                        WHC_LOGI "         find upstream dev= $upstream!"
                        break
                    }

                }
            done

        fi # end upstream valid

        upre="$upstream"
    fi # end direct neighbor

    eval "$1=$upre"
    eval "$2=$upre_ip"
    WHC_LOGD " re local connmap $connmap with upnode $upre_ip@$upre"
    __re_hyt_connmap2backhauls "$connmap" $3 $4

    # store RE backhauls result for metric
    if [ -n "eval echo '$'$4" ]; then
        mt_buff="result:success"
        mt_buff="${mt_buff}\nupstream: `eval echo '$'$1`"
        mt_buff="${mt_buff}\nupstream_ip: `eval echo '$'$2`"
        mt_buff="${mt_buff}\nbackhauls: `eval echo '$'$3`"
        mt_buff="${mt_buff}\nbackhauls_qa: `eval echo '$'$4`"

        # set bmp for backhaul and backhaul_qa also
        local bh_bmp
        local bh_qa_bmp
        __backhaul2bmp "`eval echo '$'$3`" bh_bmp && {
            __backhaul_qa2bmp "`eval echo '$'$4`" $bh_bmp bh_qa_bmp
            mt_buff="${mt_buff}\nbmp_backhauls: $bh_bmp"
            mt_buff="${mt_buff}\nbmp_backhauls_qa: $bh_qa_bmp"
        } || {
            WHC_LOGI " *except on get backhauls bmp, bhs=`eval echo '$'$3`"
            ret=$ERR_METRIC_NOT_LINK
        }

    else
        ret=$ERR_METRIC_NOT_LINK
        mt_buff="result:fail"
        WHC_LOGI " re get link metric, fail of NO qa_list"
    fi

    WHC_LOGD "$mt_buff"
    xqwhc_metric_write "`echo -e "$mt_buff"`"
    return $ret
}

# get active bakchauls on RE, should always called on RE node
# $1: output hyt active backhauls
# $2: output QA of active backhauls, order according to $1
__hyt_get_backhauls_re_abandon()
{
    local bhs="$1"
    local qas="$2"

    ### get eth backhaul
    nlal_check_eth_backhaul && {
        eval "append $bhs eth"
        eval "append $qas good"

        local flag=`uci -q get repacd.BackhaulMgr.MiwifiEthBackBaulMonopoly`
        [ -z "$flag" ] && flag=1
        [ "$flag" = "1" ] && {
            WHC_LOGI " RE has eth backhaul mono, will ign wlan bhs in repacd-run!"
            return 0
        }
    }

    ### get wifi backhaul in active
    local raw_list=""
    nlal_get_sta_ifaces "$NETWORK_PRIV" raw_list || {
        WHC_LOGD " RE find no wlan backhauls!"
        #return $ERR_NO_BACKHAUL
    }

    # if sta iface is assoc?
    #local state=""
    #local bssid=""
    #local rssi=""
    local bh=""
    local qa=""
    for iface in $raw_list; do
        nlal_check_sta_assoced $iface && {
            nlal_get_wiface_freq $iface bh
            __re_get_wifi_bh_qa $iface qa

            eval "append $bhs $bh"
            eval "append $qas $qa"
        }

     # old version abandon
      if false; then
        state=`wpa_cli -i $iface -p /var/run/wpa_supplicant-$iface status | awk -F= '/wpa_state/ {print $2}'`
        bssid=`wpa_cli -i $iface -p /var/run/wpa_supplicant-$iface status | awk -F= '/bssid/ {print $2}'`
        if [ "$state" = "COMPLETED" ]; then
            # check iface type
            bh=`iwlist $iface channel 2>&1 | grep -e "Current Frequency" | grep -o ".\." | sed 's/\./g/'`
            eval "append $bhs $bh"

            # get backhaul qa between ap_bssid
            rssi=`wlanconfig $iface list 2>/dev/null | grep "$bssid" | awk '{print $6}'`
            [ "$rssi" -lt 20 ] && qa="poor"
            [ "$rssi" -le 50 ] && qa="mid"
            [ "$rssi" -gt 60 ] && qa="good"
            eval "append $qas $qa"
        fi
      fi
    done

    #WHC_LOGI " active backhaul list=$bhs, qas=$qas"
    [ -n \"\${$bhs}\" ]
}

# ret msg of get_status
# "message": {
#    "role": "RE",
#    "ip": "192.168.31.2",
#    "ver": "1.0.100",
#    "channel": "release",
#    "sta_list": [
#        {
#            "mac": "1:2:3:4:5:0",
#            "ip": "192.168.31.10"
#        },
#        {
#            "mac": "1:2:3:4:5:1",
#            "ip": "192.168.31.11"
#        }
#    ]
# }
xqwhc_get_self_status()
{
    # hyt raw td info & ME head
    local info=""
    __hyt_info_local "td s2" || {
        message="\" error, hyt info!\""
        WHC_LOGE " $message"
        return $ERR_HYT_INFO
    }

    # get self addr from info
    local me="$(__hyt_get_td_me "$info")"
    local dbmac="$(__hyt_get_td_db_addr "$me")"
    local dbip="$(__hyt_get_td_db_ip "$me")"

    ## check if node valid?

    # get self software version
    local channel=`uci get /usr/share/xiaoqiang/xiaoqiang_version.version.CHANNEL`
    local version=`uci get /usr/share/xiaoqiang/xiaoqiang_version.version.ROM`

    # get stas direct assoc
    # hyt legacy devices is not stable
    # maybe trafficd is a choice?
    # TO do or TO redefine?


    # get role from repacd
    # if Role = RE, get active backhauls
    local role=`uci -q get repacd.repacd.Role`
    local backhauls=""
    local backhauls_qa=""
    local up_node=""
    local up_node_ip=""

    if [ "CAP" = "$role" ]; then
    # compose message jstr
    message="{\"role\":\"$role\",\
\"addr\":\"$dbmac\",\
\"ip\":\"$dbip\",\
\"channel\":\"$channel\",\
\"ver\":\"$version\"\
}"
        return 0
    fi


    # status on RE, append more json keys
    role="RE"
    local bh_list=""
    local qa_list=""

    # get cap addr from $db_all
    local db_all=$(__hyt_get_td_db_all "$info")
    local cap_addr="$(__re_hyt_get_td_cap_addr "$db_all")"

    if __re_hyt_get_backhauls up_node up_node_ip bh_list qa_list; then
        for bh in $bh_list; do
            append backhauls "\"$bh\""
        done
        backhauls=${backhauls// /,}
        # backhauls="2g" "5g"

        for qa in $qa_list; do
            append backhauls_qa "\"$qa\""
        done
        backhauls_qa=${backhauls_qa// /,}
        # backhauls="poor", "mid", "good"

        # if up_node_ip null, port from arp, maybe from trafficd hw?
        [ -z "$up_node_ip" ] && {
            local macstr="`echo -n $up_node | sed 'y/ABCDEF/abcdef/'`"
            up_node_ip="`cat /proc/net/arp | grep -w "$macstr" | grep -E -o "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"`"
        }

    # compose message jstr
    message="{\"role\":\"$role\",\
\"addr\":\"$dbmac\",\
\"ip\":\"$dbip\",\
\"upstream\":\"$up_node\",\
\"upstream_ip\":\"$up_node_ip\",\
\"cap_addr\":\"$cap_addr\",\
\"backhauls\":[$backhauls],\
\"backhauls_qa\":[$backhauls_qa],\
\"channel\":\"$channel\",\
\"ver\":\"$version\"\
}"

    else
    # compose message without connect
    message="{\"role\":\"$role\",\
\"addr\":\"$dbmac\",\
\"ip\":\"$dbip\",\
\"upstream\":\"\",\
\"upstream_ip\":\"\",\
\"cap_addr\":\"\",\
\"backhauls\":[],\
\"backhauls_qa\":[],\
\"channel\":\"$channel\",\
\"ver\":\"$version\"\
}"

    fi

    return 0
}

# get active bakchauls of a given RE node, should always called on CAP
# $1: output hyt active backhauls
# $2: output QA of active backhauls, order according to $1
__hyt_get_backhauls_cap_abandon()
{
    local bhs=""
    local qas=""

    # extract re connnect bhs from "hyt td s2" -- DB
    #local patn_di="Remote connections (Directly connected to self):"
    #local patn_indi="Remote connections (Not directly connected to self):"
    local list="WLAN2G WLAN5G ETHER"
    local rconn=""
    local patn=""
    if [ "$relation" == "Direct Neighbor" ]; then
        rconn="`echo "$db" | sed -n '/(Directly connected to self):/,/(Not directly connected to self):/ p'`"
        patn=".*Yes"    # must set direct flag to Yes
    else
        rconn="`echo "$db" | sed -n '/(Not directly connected to self):/,/[0-9]+ Bridged addresses:/ p'`"
        patn=".*"
    fi

    echo "$rconn" | grep "WLAN2G $patn"  -A 1 | grep -q "BSSID: ..\:..\:..\:..\:..\:.." && {
        append bhs "2g"
        # stub backhauls_qa, link qa must obtain from remote RE node
        append qas "good"
    }
    echo "$rconn" | grep "WLAN5G $patn"  -A 1 | grep -q "BSSID: ..\:..\:..\:..\:..\:.." && {
        append bhs "5g"
        # stub backhauls_qa, link qa must obtain from remote RE node
        append qas "good"
    }
    #[ `echo "$rconn" | grep "ETHER $patn"  -A 1 | grep -q "BSSID: ..\:..\:..\:..\:..\:.."` ] && eval "append $bhs eth"


    #echo "@@@ $bhs;; $qas"
    eval "$1=\"$bhs\""
    eval "$2=\"$qas\""
}


# CAP's perspective to get backhauls to RE db,  ONLY called on CAP
# $1: input, single db info
# $2: output, upstream addr
#      likely, upstream = CAP/RE(wlan bhs); but for distant neighber with eth bh, however, upstream is not reliable!
# $3: output, bhs
# $4: output, bh_qas
__cap_hyt_get_backhauls_bydb()
{
    local db="$1"
    
    local __upnode="$(__hyt_get_td_db_upstream "$db")"
    local __relation="$(__hyt_get_td_db_relation "$db")"
    local __connmap=""

    if __if_relation_direct "$__relation"; then
        __connmap="$(__hyt_get_td_db_connmap "$db")"

        WHC_LOGD "  RE $dbmac direct to CAP, get precise backhauls and bh_qas, map $__connmap "
        __upnode="$cap_addr"

    else
        WHC_LOGD "  RE $dbmac distant to CAP, for a precise topology, MUST request on RE itself!"
    fi

    eval "$2=$__upnode"
    __cap_hyt_connmap2backhauls "$__connmap" "$3" "$4"
}


# get a raw topology, called on CAP
# 180524: for only wlan backhauls, this handle will offer a precise topography
#         but for eth backhaul situation, plus with RE as distant neitgher, 
#         uplayer MUST launch xqwhc_status method on remote RE to get right upstream node for precise topography
xqwhc_get_topology()
{
    local cap=""
    local re_list=""

    # get role from repacd
    # if Role = RE, get active backhauls
    local role=`uci -q get repacd.repacd.Role`
    [ "$role" != CAP ] && {
        message="\" error, not CAP\""
        WHC_LOGE " $message"
        return $ERR_ROLE_NOT_CAP
    }

    # hyt raw td info & ME head
    local info=""
    __hyt_info_local "td s2" || {
        message="\" error, hyt info!\""
        WHC_LOGE " $message"
        return $ERR_HYT_INFO
    }

    # get self addr from info head --ME:
    local me="$(__hyt_get_td_me "$info")"
    local cap_addr="$(__hyt_get_td_db_addr "$me")"
    local cap_ip="$(__hyt_get_td_db_ip "$me")"

    # get whc ssid pswd
    local whc_ssid="$(str_escape `uci -q get wireless.@wifi-iface[0].ssid`)"
    local whc_pswd="$(str_escape `uci -q get wireless.@wifi-iface[0].key`)"

    # get re node from info --DB:
    local db_all="$(__hyt_get_td_db_all "$info")"
    #local re_cnt="`echo "$info" | grep -E "^\-\- DB \([0-9]+ entries\)" | grep -o "[0-9]"`"
    local re_cnt="$(__hyt_get_td_db_cnt "$db_all")" 
    [ -z "$re_cnt" ] && re_cnt=0

    # compose cap object
    cap="{\"addr\":\"$cap_addr\",\
\"ip\":\"$cap_ip\",\
\"whc_ssid\":\"$whc_ssid\",\
\"whc_pswd\":\"$whc_pswd\",\
\"re_cnt\": $re_cnt\
}"

    # get re_list
    local re_list=""
    local re_node=""
    if [ "$re_cnt" -gt 0 ]; then
        local db=""
        local upnode=""
        local dbmac=""
        local dbip=""
        local relation=""
        local backhauls=""
        local backhauls_qa=""

        for ii in `seq 1 $re_cnt`; do
            # get single re db info, pattern from #? QCA IEEE 1905.1 to Bridged addresses:
            db="$(__hyt_get_td_db_single_byidx "$db_all" "$ii")"
            dbmac="$(__hyt_get_td_db_addr "$db")"
            dbip="$(__hyt_get_td_db_ip "$db")"

            local relation="$(__hyt_get_td_db_relation "$db")"
            local upnode=""
            local bh_list=""
            local qa_list=""

            __cap_hyt_get_backhauls_bydb "$db" upnode bh_list qa_list 

            for bh in $bh_list; do
                append backhauls "\"$bh\""
            done
            backhauls=${backhauls// /,}

            for qa in $qa_list; do
                append backhauls_qa "\"$qa\""
            done
            backhauls_qa=${backhauls_qa// /,}

            re_node="{\
\"addr\":\"$dbmac\",\
\"ip\":\"$dbip\",\
\"relation\":\"$relation\",\
\"upstream\":\"$upnode\",\
\"backhauls\":[$backhauls],\
\"backhauls_qa\":[$backhauls_qa]\
},"

            WHC_LOGD "  RE $dbmac bhs=$backhauls, qas=$backhauls_qa "

            append re_list "$re_node"
        done

        re_list=${re_list%,}

    else
        re_list=[]
    fi


    message="{
\"cap\":$cap,\
\"re_list\":["$re_list"]\
}"

    return 0
}

# get recnt, caller should make sure situation is CAP
xqwhc_get_recnt()
{
    xqwhc_get_topology
    local cnt=""

    json_load "$message" >/dev/null 2>&1
    json_select "cap" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        json_get_var cnt "re_cnt"
        #json_select ".."
    fi

    [ -z "$cnt" ] && cnt=0
    echo -n "$cnt"
    return "$cnt"
}

# this is only running on RE, cause it checkout backhaul connection.
# only get a valid CAP addr return ok, not a metric.
xqwhc_precise_check()
{
    # confirm role
    local role=`uci -q get repacd.repacd.Role`
    [ "CAP" = "$role" ] && {
        WHC_LOGE " precise check only called on RE, self no RE!"
        return $ERR_ROLE_NOT_RE
    }

    local info=""
    __hyt_info_local "td s2" || {
        message="\" error, hyt info!\""
        WHC_LOGE " $message"
        return $ERR_HYT_INFO
    }

    # get self addr from info
    local me="$(__hyt_get_td_me "$info")"
    local dbmac="$(__hyt_get_td_db_addr "$me")"
    local dbip="$(__hyt_get_td_db_ip "$me")"

    # get cap addr from $db_all
    # check if get the upstream/cap_addr to confirm that RE self is connected
    local db_all=$(__hyt_get_td_db_all "$info")
    local cap_addr="$(__re_hyt_get_td_cap_addr "$db_all")"
    [ -z "$cap_addr" -o "00:00:00:00:00:00" = "$cap_addr" ] && {
        WHC_LOGI "  precise_check, NOT connectted to CAP!"
        return $ERR_NOT_CONNECTTED
    }

    return 0
}

# check to update RE link metrics buff file
# return 0: linkup
# return else: no link
xqwhc_re_linkmetric()
{
    # confirm role
    local role=`uci -q get repacd.repacd.Role`
    [ "CAP" = "$role" ] && {
        WHC_LOGI " precise check only called on RE, self no RE!"
        return $ERR_ROLE_NOT_RE
    }

    local info=""
    __hyt_info_local "td s2" || {
        message="\" error, hyt info!\""
        WHC_LOGE " $message"
        return $ERR_HYT_INFO
    }

    # get cap addr from $db_all
    # check if get the upstream/cap_addr to confirm that RE self is connected
    local db_all=$(__hyt_get_td_db_all "$info")
    local cap_addr="$(__re_hyt_get_td_cap_addr "$db_all")"
    
    local up_node up_node_ip bh_list qa_list
    if __re_hyt_get_backhauls up_node up_node_ip bh_list qa_list; then
        #xqwhc_metric_get_summary
        return 0
    fi

    return $ERR_METRIC_NOT_LINK
}

# check RE ping CAP ret
# return 0: linkup
# return else: no link
xqwhc_gateway_ping()
{
    local ping_file="/tmp/log/xqwhc_gateway_ping"
    local gw_ip="$(nlal_get_gw_ip lan)"
    local ret="`cat $ping_file 2>/dev/null`"
    [ "$ret" = "ok" ] && return 0
    if [ -n "$gw_ip" ]; then
        ping $gw_ip -q -w 3 -c 3 2>&1 >/dev/null && echo "ok" > "$ping_file" || echo "fail" > "$ping_file" &
    else
        WHC_LOGI "  NO find valid gateway!"
    fi

    return 1
}

# check RE assoc CAP ret
# return 0: associated
# return else: no assoc
xqwhc_assoc_check()
{
    local iface_5g_bh="`uci get misc.backhauls.backhaul_5g_sta_iface 2>/dev/null`"
    [ -z "$iface_5g_bh" ] iface_5g_bh="wl01"
    wpa_cli -p /var/run/wpa_supplicant-$iface_5g_bh list_networks | grep -q "CURRENT" && return 0

    [ "$BH_METHOD" -eq "$USE_DUAL_BAND_IND_VAP_BH" -o "$BH_METHOD" -eq "$USE_DUAL_BAND_BH" ] && {
        local iface_2g_bh="`uci get misc.backhauls.backhaul_2g_sta_iface 2>/dev/null`"
        [ -z "$iface_2g_bh" ] iface_2g_bh="wl11"
        wpa_cli -p /var/run/wpa_supplicant-$iface_2g_bh list_networks | grep -q "CURRENT" && return 0
    }

    if xqwhc_gateway_ping; then
        WHC_LOGI "  assoc_check: Find valid gateway!"
        return 0
    fi

    return 1
}

# getmetric bmp from buff
# LSB 0-3: backhaul bmp; MSB 4-7: backhaul qa bmp
# return: LSB0-3: backhauls bmp 2g 5g resv eth,  MSB 4-7: backhauls qa bmp
# bit mapping for backhauls represent
# eg:  backhauls RE to CAP with poor 5g + good 2g
#   ret value will be 0x13 = 19
xqwhc_re_getmetric_abandon()
{
    [ -f "$XQWHC_LINK_METRICS" ] || return 0;
    bh_bmp=`cat "$XQWHC_LINK_METRICS" | grep -E "^bmp_backhauls:" | awk -F: '{print $2}'`
    qa_bmp=`cat "$XQWHC_LINK_METRICS" | grep -E "^bmp_backhauls_qa:" | awk -F: '{print $2}'`

    [ -z "$bh_bmp" ] && bh_bmp=0
    [ -z "$qa_bmp" ] && qa_bmp=0
    
    [ "$BH_2G_METRIC_WEIGHT" -eq 0 ] && qa_bmp="$((qa_bmp & 14))"  # 14=b1110, metric exclude 2g backhaul

    return $(((qa_bmp<<4) + bh_bmp))
}

xqwhc_re_getmetric_str_abandon()
{
    [ -f "$XQWHC_LINK_METRICS" ] || return 1;

    local thres=""
    [ "$BH_2G_METRIC_WEIGHT" -gt 0 ] && thres="$((1<<(BACKHAUL_BMP_2g + 4)))" || thres="$((1<<(BACKHAUL_BMP_5g + 4)))"

    xqwhc_re_getmetric
    ret=$?
    if [ "$ret" -ge "$thres" ]; then
        echo -n "good"
    elif [ "$ret" -gt 0 ]; then
        echo -n "poor"
    else
        :
    fi
    return 0
}

