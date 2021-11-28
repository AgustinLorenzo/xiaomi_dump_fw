#!/bin/sh
#logger -p notice -t "hotplug.d" "10-phy_check.sh: run because of $INTERFACE $ACTION"

if [ "$INTERFACE" = "wan" -a "$ACTION" = "ifup" ]; then
        wan_speed=$(uci -q get xiaoqiang.common.WAN_SPEED)
        [ $wan_speed -eq 0 ] && return

        cur_wan_speed=$(ethtool eth1 | grep "Speed" | cut -d " " -f 2 | cut -d "M" -f 1)
        if [ $cur_wan_speed != $wan_speed ]; then
                case "$wan_speed" in
#               	0)
#                       	reg=0x23f;;
					10)
							reg=0x033;;
					100)
							reg=0x03c;;
					1000)
							reg=0x230;;
					*)
							return;;
                esac

                wan_port=$(uci get misc.sw_reg.sw_wan_port)
                ssdk_sh port autoAdv set $wan_port $reg
                ssdk_sh port autoNeg restart $wan_port
        fi
fi
