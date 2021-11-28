#!/bin/sh
#  xiaomi whc backhaul quality metric unified interface

export XQWHC_METRIC_BUFF="/tmp/run/xqwhc_metrics"
export XQWHC_METRIC_RT="/tmp/run/whcrtmt"
MT_LOCKF="/tmp/lock/xqwhc_metric.lock"
MT_TIMEOUT=5

XQLOGTAG="xqwhc_metric"

# bit mapping for backhauls represent
export BACKHAUL_BMP_2g=0
export BACKHAUL_BMP_5g=1
export BACKHAUL_BMP_resv=2
export BACKHAUL_BMP_eth=3
export BACKHAUL_QA_BMP_GOOD=1
export BACKHAUL_QA_BMP_POOR=0
export BH_2G_METRIC_WEIGHT=0       # for qca son, experience takes most weight on 5G, so in ONLY 2G case. show as POOR metric

export METRIC_GOOD=0
export METRIC_POOR=91
export METRIC_FAIL=92


__MT_LOG()
{
    local stderr=''
    logger $stderr -p user.info -t "$XQLOGTAG" "$1"
}

__TRACE()
{
    # trace caller
    local ppid=$PPID
    echo -n "(ppid:$ppid:<`cat /proc/${ppid}/cmdline`>)"
    #ppid=`cat /proc/${ppid}/status | grep PPid | grep -o "[0-9]*"`
    #__MT_LOG *parent ppid $ppid, cmd=<`cat /proc/${ppid}/cmdline`>"
}

__UNLOCK()
{
    lock -u "$MT_LOCKF"
}

__LOCK()
{
    timeout -t $MT_TIMEOUT lock "$MT_LOCKF" 2>/dev/null || {
        __MT_LOG " *warning, unlock $MT_LOCKF"
        __UNLOCK
    }
}

trap "__UNLOCK; exit 1" SIGHUP SIGINT SIGTERM


__ts_get()
{
    local ts="`date +%Y%m%d-%H%M%S`:`cat /proc/uptime | awk '{print $1}'`"
    echo -n "timestamp:$ts"
}


### write metric buff file
# caller should write all metric info into buff as a atomic op

###### metric buff format
#result:success
#upstream: 50:64:2B:B5:7F:77
#upstream_ip: 192.168.31.1
#backhauls: 2g 5g resv
#backhauls_qa: good good
#bmp_backhauls: 3
#bmp_backhauls_qa: 3
#timestamp:20190201-180011@518.34

list="result upstream upstream_ip backhauls backhauls_qa bmp_backhauls bmp_backhauls_qa"
xqwhc_metric_write()
{
    local buff="$1"

    __LOCK

    # check valid
    echo > ${XQWHC_METRIC_BUFF}_tmp
    for ele in $list; do
        echo "$buff" | grep -w "$ele" >> ${XQWHC_METRIC_BUFF}_tmp || {
            __MT_LOG "  *metric element $ele lost, check input buff! echo $buff"
            return 1
        }
        # if result fail, break out
        [ "$ele" = "result" ] && {
            echo "$buff" | grep -w "$ele" | grep -q "fail" && {
                __MT_LOG "   metric fail"
                break
            }
        }
    done
    echo "$(__ts_get)" >> ${XQWHC_METRIC_BUFF}_tmp

    mv -f "$XQWHC_METRIC_BUFF" "${XQWHC_METRIC_BUFF}_pre" 2>/dev/null
    mv -f ${XQWHC_METRIC_BUFF}_tmp $XQWHC_METRIC_BUFF
    sync

    __UNLOCK
}

# flush metric buff
xqwhc_metric_flush()
{
    __LOCK
    rm -rf ${XQWHC_METRIC_BUFF}* $XQWHC_METRIC_RT
    sync
    __UNLOCK
}


# read metric buff file 
xqwhc_metric_dump()
{
    __LOCK
    [ -f "$XQWHC_METRIC_BUFF" ] && {
        cat "$XQWHC_METRIC_BUFF" 
    } || {
        __MT_LOG " *warn, NO metricbuff $(__TRACE)"
    }
    __UNLOCK
}


# get upnode mac and ip
# result: $mac;$ip
xqwhc_metric_get_upstream()
{
    __LOCK
    local buff="`cat $XQWHC_METRIC_BUFF`"
    __UNLOCK
    upmac="`echo "$buff" | grep "^upstream:" | grep -o "..:..:..:..:..:.."`"
    upip="` echo "$buff" | grep "^upstream_ip:" | grep -E -o "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" `"
    echo -n "${upmac};${upip}"
}


# result & backhaul_qa, in summary beheave
# return: fail, good, poor
xqwhc_metric_get_summary()
{
    __LOCK
    local buff="`cat $XQWHC_METRIC_BUFF`"
    __UNLOCK

    local res bh_bmp qa_bmp
    res="`echo "$buff" | grep "^result:" | awk -F: '{print $2}'`"
    [ "$res" = "success" ] || return "$METRIC_FAIL"

    bh_bmp="`echo "$buff" | grep "^bmp_backhauls:" | awk -F: '{print $2}'`"
    [ -z "$bh_bmp" -o "$bh_bmp" -eq 0 ] && return "$METRIC_POOR"
    
    qa_bmp="`echo "$buff" | grep "^bmp_backhauls_qa:" | awk -F: '{print $2}'`"
    [ -z "$qa_bmp" -o "$qa_bmp" -eq 0 ] && return "$METRIC_POOR"

    # consider 2G metric weight sense, if NO weight, ignore 2G backhaul qa
    local thres="$((1<<BACKHAUL_BMP_5g))"
    [ "$BH_2G_METRIC_WEIGHT" -gt 0 ] && thres="$((1<<BACKHAUL_BMP_2g))"
    [ "$qa_bmp" -ge "$thres" ] && return $METRIC_GOOD || return $METRIC_POOR
}

xqwhc_metric_get_str()
{
    local ret=$METRIC_GOOD
        xqwhc_metric_get_summary
        ret=$?
        if [ "$ret" = "$METRIC_GOOD" ]; then
            res="good"
        elif [ "$ret" = "$METRIC_POOR" ]; then
            res="poor"
        else
            #[ "$ret" = "$ERR_METRIC_NOT_LINK" ]
            res="fail"
        fi  
        echo -n "$res"

    return $ret
}


# ger verbose backhaul and qa
# return as bitmap
###########
# LSB 0-3: backhaul bmp order in 2g/5g/resv/eth, bit=1 represent backhaul is linkup.
# MSB 4-7: backhaul quality bmp, order in 2g/5g/resv/eth, bit=1 represent backhaul is linkup and metric good.
# eg:  backhauls RE to CAP with poor 5g + good 2g
#   ret value will be 0x13 = 19
xqwhc_metric_get_verbose()
{
    __LOCK
    local bh_bmp qa_bmp
    local buff="`cat $XQWHC_METRIC_BUFF`"
    __UNLOCK

    bh_bmp="`echo "$buff" | grep -E "^bmp_backhauls:" | awk -F: '{print $2}'`"
    qa_bmp="`echo "$buff" | grep -E "^bmp_backhauls_qa:" | awk -F: '{print $2}'`"
    [ -z "$bh_bmp" ] && bh_bmp=0
    [ -z "$qa_bmp" ] && qa_bmp=0
    
    [ "$BH_2G_METRIC_WEIGHT" -eq 0 ] && qa_bmp="$((qa_bmp & 14))"  # 14=b1110, metric exclude 2g backhaul
    #echo -n $(((qa_bmp<<4) + bh_bmp))
    return $(((qa_bmp<<4) + bh_bmp))

}


ret=0
case $1 in
    getmtv)
        xqwhc_metric_get_str
        ret=$?
      ;;
    getmts)
        xqwhc_metric_get_summary
        ret=$?
        if [ "$ret" = "$METRIC_GOOD" ]; then
            res="good"
        elif [ "$ret" = "$METRIC_POOR" ]; then
            res="poor"
        else
            #[ "$ret" = "$ERR_METRIC_NOT_LINK" ]
            res="fail"
        fi  
        echo -n "$res"
      ;;
    *)
        :
      ;;
esac

return $ret

