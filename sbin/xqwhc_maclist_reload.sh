#!/bin/sh

### activate wifi black/white maclist after sync from gateway router / whc_CAP

# this script warm process maclist on wifi ap iface
. /lib/functions.sh

LOGI()
{
    logger -s -p 1 -t "xqwhc_maclist" "$1"
}

__wifi_stalist()
{
    echo -n "`wlanconfig $1 list 2>&1 | grep -Eo "..:..:..:..:..:.." | xargs`"
}

__maclist_flush()
{
    local ifa="$1"
    iwpriv $ifa maccmd_sec 3
}

__maclist_disable()
{
    local ifa="$1"
    iwpriv $ifa maccmd_sec 0
}

__maclist_active_deny()
{
    local ifa="$1"

    iwpriv $ifa maccmd_sec 2

    # add all maclist and process mac DO in assoclist
    for umac in $maclist; do
        umac="`echo -n $umac | sed 'y/ABCDEF/abcdef/'`"

        iwpriv $ifa addmac_sec $umac

        # if umac in assoc list, kick it
        local assoclist="$(__wifi_stalist $ifa)"
        list_contains assoclist $umac && {
            LOGI " $umac in deny maclist, kick it from $ifa "
            iwpriv $ifa  kickmac $umac
        }
    done
}

__maclist_active_allow()
{
    local ifa="$1"

    iwpriv $ifa maccmd_sec 1

    # add all maclist and process mac NOT in assoclist
    for umac in $maclist; do
        iwpriv $ifa addmac_sec $umac
    done

    # if asmac NOT in allow maclist, kick it
    local assoclist="$(__wifi_stalist $ifa)"
    for umac in $assoclist; do
        umac="`echo -n $umac | sed 'y/abcdef/ABCDEF/'`"
        list_contains maclist $umac || {
            LOGI " $umac NOT in allow maclist, kick it from $ifa "
            iwpriv $ifa  kickmac $umac
        }
    done
}


# wifi ap iface
iflist="wl0 wl1"
#nlal_get_wifi_apiface_bynet $NETWORK_PRIV iflist
LOGI " iflist=$iflist"

# fileter type deny / allow
macfilter="`uci -q get wireless.@wifi-iface[0].macfilter`"
maclist="`uci -q get wireless.@wifi-iface[0].maclist | sed 'y/ABCDEF/abcdef/' `"
LOGI " wifi macfilter [$macfilter]:[$maclist]"

for ifa in $iflist; do
    __maclist_flush $ifa
    __maclist_disable $ifa

    if [ "$macfilter" = "deny" ]; then
        __maclist_active_deny $ifa
    elif [ "$macfilter" = "allow" ]; then
        __maclist_active_allow $ifa
    else
        :
    fi
done




















