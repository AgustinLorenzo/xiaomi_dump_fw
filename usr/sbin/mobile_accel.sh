#!/bin/sh
# mobile accel

maccel_logger()
{
    #echo "maccel: $1" > /dev/console
    logger -t maccel "$1"
}

maccel_usage()
{
    echo "usage: ./mobile_accel.sh on|check|enable|disable|cln"
    echo "value: on client_ip client_mac mode -- enable maccel"
    echo ""
}

maccel_clean()
{
	local db_cnt=$(uci -q get mobile_accel.settings.db_record)
	for c_name in `awk '/^config.*client/{print$3}' /etc/config/mobile_accel |tr "\'\"" " " `
	do
		db_cnt=`expr $db_cnt + 1`
		local c_hname=$(uci -q get mobile_accel.$c_name.hostname)
		local ts_on=$(uci -q get mobile_accel.$c_name.ts_on)
		local ts_update=$(uci -q get mobile_accel.$c_name.ts_update)
		local mode=$(uci -q get mobile_accel.$c_name.mode)
		uci delete mobile_accel.$c_name

		#add record to xqdb
		#c_mac=${c_name:0:2}:${c_name:2:2}:${c_name:4:2}:${c_name:6:2}:${c_name:8:2}:${c_name:10:2}
		#lua /usr/sbin/mobile_accel_db.lua add $c_mac $c_ip $c_hname $mode $ts_on $ts_update
	done
	uci set mobile_accel.settings.client_active='0'
	uci set mobile_accel.settings.db_record=$db_cnt
	uci commit mobile_accel

	[ $db_cnt -gt 250 ] && {
		local del_num=`expr $db_cnt - 250`
		maccel_db_del $db_num 250
	}
}

#make sure : mobile_accel_db records <= 250
maccel_db_del()
{
	local del_num=$1
	local db_cnt=$2
	[ $del_num -gt 0 ] && {
		#echo "maccel_db_del: $del_num" > /dev/console
		#lua /usr/sbin/mobile_accel_db.lua del $del_num
		uci set mobile_accel.settings.db_record=$db_cnt
		uci commit mobile_accel
	}
}

maccle_iptables_set()
{
	local op="-D"
	local c_ip=$2

	[ "$1" = "add" ] && op="-I"
	iptables -t mangle $op FORWARD -d $c_ip -j DSCP --set-dscp 48
}

maccel_disabled()
{
	local cnt=$(uci -q get mobile_accel.settings.client_active)
	uci set mobile_accel.settings.enabled='0'
	uci set mobile_accel.settings.client_active='0'
	uci commit mobile_accel
	[ "$cnt" = "0" ] && return

	local db_cnt=$(uci -q get mobile_accel.settings.db_record)
	for c_name in `awk '/^config.*client/{print$3}' /etc/config/mobile_accel |tr "\'\"" " " `
	do
		db_cnt=`expr $db_cnt + 1`
		local c_ip=$(uci -q get mobile_accel.$c_name.ip)
		local ts_on=$(uci -q get mobile_accel.$c_name.ts_on)
		local ts_update=$(date -u +%s)
		local mode=$(uci -q get mobile_accel.$c_name.mode)
		local c_hname=$(uci -q get mobile_accel.$c_name.hostname)
		uci delete mobile_accel.$c_name

		#close accel
		maccle_iptables_set del $c_ip
		del_ecm_record $c_ip

		#add record to xqdb
		#c_mac=${c_name:0:2}:${c_name:2:2}:${c_name:4:2}:${c_name:6:2}:${c_name:8:2}:${c_name:10:2}
		#lua /usr/sbin/mobile_accel_db.lua add $c_mac $c_ip $c_hname $mode $ts_on $ts_update
	done
	uci set mobile_accel.settings.db_record=$db_cnt
	uci commit mobile_accel

	[ $db_cnt -gt 250 ] && {
		local del_num=`expr $db_cnt - 250`
		maccel_db_del $db_num 250
	}
}

maccel_check()
{
	local db_cnt=$(uci -q get mobile_accel.settings.db_record)
	local cnt=$(uci -q get mobile_accel.settings.client_active)
	for c_name in `awk '/^config.*client/{print$3}' /etc/config/mobile_accel |tr "\'\"" " " `
	do
		local ts_update=$(uci -q get mobile_accel.$c_name.ts_update)
		local ts_cur=$(date -u +%s)
		local diff=`expr $ts_cur - $ts_update`

		[ $diff -ge 540 ] && {
			[ $cnt -gt 0 ] && {
				cnt=`expr $cnt - 1`
				uci set mobile_accel.settings.client_active=$cnt
			}
			db_cnt=`expr $db_cnt + 1`
			local ts_on=$(uci -q get mobile_accel.$c_name.ts_on)
			local mode=$(uci -q get mobile_accel.$c_name.mode)
			local c_hname=$(uci -q get mobile_accel.$c_name.hostname)
			local c_ip=$(uci -q get mobile_accel.$c_name.ip)
			uci delete mobile_accel.$c_name

			maccel_logger "stop accel: $c_name, $c_ip, $c_hname"
			#close accel
			maccle_iptables_set del $c_ip
			del_ecm_record $c_ip

			#add record to xqdb
			#c_mac=${c_name:0:2}:${c_name:2:2}:${c_name:4:2}:${c_name:6:2}:${c_name:8:2}:${c_name:10:2}
			#lua /usr/sbin/mobile_accel_db.lua add $c_mac $c_ip $c_hname $mode $ts_on $ts_update
		}
	done
	uci set mobile_accel.settings.db_record=$db_cnt
	uci commit mobile_accel

	[ $db_cnt -gt 300 ] && {
		local del_num=`expr $db_cnt - 250`
		maccel_db_del $db_num 250
	}
}

del_ecm_record()
{
	[ -z "$1" ] && return
	local ecm_list=$(ecm_dump.sh | grep sip_address=$1)
	[ -z "$ecm_list" ] && return

	for ecm_record in $ecm_list
	do
		serial=$(echo $ecm_record | awk -F'.' '{print $3}')
		echo s/$serial > /sys/kernel/debug/ecm/ecm_classifier_nl/cmd
	done

	#usleep 20000
	sleep 1
	for ecm_record in $ecm_list
	do
		serial=$(echo $ecm_record | awk -F'.' '{print $3}')
		echo S/$serial > /sys/kernel/debug/ecm/ecm_classifier_nl/cmd
	done
}

maccel_on()
{
	local client_ip=$1
	local client_mac=$2
	local mode=$3
	local c_exist=$(uci -q get mobile_accel.$name)
	local cnt=$(uci -q get mobile_accel.settings.client_active)
	if [ $cnt -ge 6 ]; then
		[ -z "$c_exist" ] && return 1
	elif [ -z "$c_exist" ]; then
		uci -q batch <<EOF
        set mobile_accel.settings.client_active=`expr $cnt + 1`
        commit mobile_accel
EOF
	fi

	if [ -z "$c_exist" ]; then
		local hostname=$(cat /tmp/dhcp.leases | grep $client_mac | awk 'NR==1 {print $4}')
		[ -z "$hostname" ] && hostname=$name
		uci -q batch <<EOF
        set mobile_accel.$name=client
		set mobile_accel.$name.hostname="$hostname"
		set mobile_accel.$name.ip="$client_ip"
		set mobile_accel.$name.mode="$mode"
		set mobile_accel.$name.ts_on=$(date -u +%s)
		set mobile_accel.$name.ts_update=$(date -u +%s)
        commit mobile_accel
EOF
		#open accel
		maccle_iptables_set add $client_ip
		del_ecm_record $client_ip
		maccel_logger "open accel: $name, $client_ip, $hostname"
	else
		local reopen_accel=0
		c_old=$(uci -q get mobile_accel.$name.ip)
		[ "$client_ip" != "$c_old" ] && {
			reopen_accel=1
			local hostname=$(cat /tmp/dhcp.leases | grep $client_mac | awk 'NR==1 {print $4}')
			[ -z "$hostname" ] && hostname=$name
			uci set mobile_accel.$name.hostname="$hostname"
			uci set mobile_accel.$name.ip="$client_ip"
		}
		uci set mobile_accel.$name.ts_update=$(date -u +%s)
		uci commit mobile_accel

		[ "$reopen_accel" = "1" ] && {
			#open accel
			maccle_iptables_set add $client_ip
			maccle_iptables_set del $c_old
			del_ecm_record $client_ip
			del_ecm_record $c_old
			maccel_logger "reopen accel: $name, $client_ip"
		}
	fi
}


[ -z "$1" ] && return 1

enabled=$(uci -q get mobile_accel.settings.enabled)
[ "$enabled" == "0" -a "$1" != "enable" ] && return

[ "$1" = "on" ] && {
	[ -z "$2" ] && return 1
	[ -z "$3" ] && return 1
	name=$(echo $3 | sed 's/://g' | tr 'A-Z' 'a-z')
}

maccel_lock="/var/run/maccel.lock"
trap "lock -u $maccel_lock; exit 1" SIGHUP SIGINT SIGTERM

lock $maccel_lock
case "$1" in
	on)
		maccel_on $2 $3 $4
		;;

	check)
		maccel_check
		;;

	enable)
		uci -q batch <<EOF
        set mobile_accel.settings.enabled='1'
        commit mobile_accel
EOF
		;;

	disable)
		maccel_disabled
		;;

	cln)
		maccel_clean
		;;
	*)
		maccel_usage
		;;
esac

lock -u $maccel_lock

return 0
