#!/bin/sh
# Copyright (C) 2020 Xiaomi

#
# $1 = opt. reset/update
# usage:
#      wan_check.sh reset/update
#

OPT=$1

case $OPT in 
    reset)
        ubus call check_wan reset
    ;;

    update)
       ubus call check_wan update
    ;;

     * ) 
        echo "usage: wan_check.sh reset/update" >&2
  ;;
esac

