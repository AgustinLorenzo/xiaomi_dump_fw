#!/bin/sh

# public for mimesh

export MIMESH_DEBUG=0 # miwifi set to 1 for test
export NETWORK_PRIV="lan"
export NETWORK_GUEST="guest"
export BHPREFIX="MiMesh"
export bh_defmgmt="psk2+ccmp"

# print level
export MIMESH_PRT_ERR=1      # erro
export MIMESH_PRT_INFO=2     # erro + info
export MIMESH_PRT_DEBUG=3    # erro + info + debug
export MIMESH_PRT_LEVEL="$MIMESH_PRT_INFO"
[ "$MIMESH_DEBUG" = "1" ] && MIMESH_PRT_LEVEL="$MIMESH_PRT_DEBUG"

LOG_FILE="/tmp/log/mimesh.log"
TMP_LOG_SIZE=600000

[ -f $LOG_FILE ] || touch $LOG_FILE

MIMESH_TRACE()
{
	local log="$1"
	#return
	local file=$LOG_FILE
	local ts="`date '+%Y%m%d-%H%M%S'`@`cat /proc/uptime | awk '{print $1}'`"
	local time="[$ts]"
	local item="${time}    ${log}"

	echo -e "$item" >> "$file" 2>/dev/null
	sync
}

RET(){
	echo -n "$1"
}

MIMESH_LOGD()
{
	[ "$MIMESH_PRT_LEVEL" -lt "$MIMESH_PRT_DEBUG" ] && return 0

	local __msg="$1"
	[ "$MIMESH_DEBUG" = "1" ] && {
		echo "mimesh_debug $__msg"
	}
	#logger -p 4 -t mimesh_debug "$__msg" 2>/dev/null
	MIMESH_TRACE "mimesh_debug $__msg"
}

MIMESH_LOGI()
{
	[ "$MIMESH_PRT_LEVEL" -lt "$MIMESH_PRT_INFO" ] && return 0

	local __msg=" $1"
	[ "$MIMESH_DEBUG" = "1" ] && {
		echo "mimesh_info $__msg"
	}
	#logger -p 3 -t mimesh_info "$__msg" 2>/dev/null
	MIMESH_TRACE "mimesh_info $__msg"
}

MIMESH_LOGE()
{
	[ "$MIMESH_PRT_LEVEL" -lt "$MIMESH_PRT_ERR" ] && return 0

	local __msg="$1"
	[ "$MIMESH_DEBUG" = "1" ] && {
		echo "mimesh_error $__msg"
	}
	#logger -p 2 -t mimesh_error "$__msg" 2>/dev/null
	MIMESH_TRACE "mimesh_error $__msg"
}

WHC_LOGD()
{
	[ "$MIMESH_PRT_LEVEL" -lt "$MIMESH_PRT_DEBUG" ] && return 0

	local __msg="$1"
	[ "$MIMESH_DEBUG" = "1" ] && {
		echo "mimesh_debug $__msg"
	}
	#logger -p 4 -t mimesh_debug "$__msg" 2>/dev/null
	MIMESH_TRACE "mimesh_debug $__msg"
}

WHC_LOGI()
{
	[ "$MIMESH_PRT_LEVEL" -lt "$MIMESH_PRT_INFO" ] && return 0

	local __msg=" $1"
	[ "$MIMESH_DEBUG" = "1" ] && {
		echo "mimesh_info $__msg"
	}
	#logger -p 3 -t mimesh_info "$__msg" 2>/dev/null
	MIMESH_TRACE "mimesh_info $__msg"
}

WHC_LOGE()
{
	[ "$MIMESH_PRT_LEVEL" -lt "$MIMESH_PRT_ERR" ] && return 0

	local __msg="$1"
	[ "$MIMESH_DEBUG" = "1" ] && {
		echo "mimesh_error $__msg"
	}
	#logger -p 2 -t mimesh_error "$__msg" 2>/dev/null
	MIMESH_TRACE "mimesh_error $__msg"
}

### 
json_get_value_sh_p()
{
	local json_str="`echo $1 | sed 's/^{//' | sed 's/}$//'`"
	local key="$2"

	#json_str=`echo $json_str | sed 's/:[ ]*/:/g' | sed 's/[ ]*\"/\"/g'`
	echo "$json_str" | grep -q "\"$key\":" || {
		RET ""
		return 1
	}

	# value is a odject {}
	local tmp=`echo "$json_str" | sed 's/.*'\"$key\"':/\1/' | sed 's/^[ ]*//'`
	echo "$tmp" | grep -qE "^\{" && {
		RET "`echo $tmp | awk -F'}' '{print $1}'`}"
		return 0
	}

	# value is a array []
	echo "$tmp" | grep -qE "^\[" && {
		RET "`echo $tmp | awk -F']' '{print $1}'`]"
		return 0
	}

	# value is a value
	tmp=`echo $tmp | awk -F',' '{print $1}' | sed 's/[ ]*$//'`
	tmp=`echo $tmp | sed 's/\}//g' | sed 's/\]//g'`
	RET "$tmp" | sed 's/^"//' | sed 's/"$//'
	return 0
}

json_get_value_sh()
{
	local val=""
	json_load "$1"
	json_get_var val "$key"

	RET "$val"
	[ -n "$val" ]
}

json_get_value()
{
	local json_str="`echo "$1" | sed 's/^\[//' | sed 's/\]$//' `"
	local key="$2"

	parse_json "$json_str" "$key"
}

id_generate()
{
	local seed=`awk -F- '{print $1}' /proc/sys/kernel/random/uuid`
	local raw=`printf %d 0x$seed`
	RET $(($raw & 0xfffff))
}

str_escape()
{
	local str="$1"
	echo -n "$str" | sed -e 's/^"/\\"/' | sed -e 's/\([^\]\)"/\1\\"/g' | sed -e 's/\([^\]\)"/\1\\"/g' | sed -e 's/\([^\]\)\(\\[^"\\\/bfnrtu]\)/\1\\\2/g' | sed -e 's/\([^\]\)\\$/\1\\\\/'
}

base64_enc()
{
	## encode and unfold mutiple line
	local str="`echo -n "$1" | base64 | sed 's/ //g'`"
	RET "$str" | awk -v RS="" '{gsub("\n","");print}'
	#RET "`echo "$1" | base64 | xargs`"
}

base64_dec()
{
	RET "`echo "$1" | base64 -d`"
}

# truncate ssid, to avoid the situation that cut a UTF-8 large CHAR beyond ASCII.
# UTF-8 Characters span vary unit of sizeof(char), may vary from 1 to 6
# 1 unit UTF8: 0xxxxxxx
# 2 units UTF8: 110xxxxx 10xxxxxx
# 3 units UTF8: 1110xxxx 10xxxxxx 10xxxxxx
# 4 units UTF8: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
## support Chinese Char and emoji
ssid_truncate()
{
	local MAX_LEN=26
	local src_str="$1"

	local src_len="${#src_str}"
	[ "$src_len" -le "$MAX_LEN" ] && {
		echo -n "$src_str"
		return 0
	}

	logger -p 3 -t "ssid_trunca" "src $src_len@[$src_str]"

	local cut_len=0
	local ch=""
	local ch_hex=0x0
	local ch_val=0
	local cur_len="$src_len"
	local utf8_ch_flag=0

	while [ "$cur_len" -gt "$MAX_LEN" -o "$utf8_ch_flag" -eq 1 ]; do
		ii="$cur_len"
		ch="`echo -n $src_str | cut -b $ii-$ii`"
		ch_hex="`echo -n $ch | hexdump | awk 'NR==1 {print $2}' | cut -b 1-2`"
		ch_val="`printf %d 0x$ch_hex`"
		#logger -p 3 -t "ssid_trunca" " ch=[$ch], ch_hex=[$ch_hex], ch_val=$ch_val"

		if [ "$ch_val" -le 128 ]; then
			# ASCII char
			utf8_ch_flag=0
		else
			# utf8 char
			if [ "$((ch_val - 128))" -lt 64 ]; then
				utf8_ch_flag=1
			else
				utf8_ch_flag=0
			fi
		fi
		cur_len=$((cur_len - 1))

	done

	local dst_str=`echo -n "$src_str" | cut -b 1-$cur_len`
	#logger -p 3 -t "ssid_trunca"  " dst_str ${#dst_str}@[$dst_str]"

	echo -n "$src_str" | cut -b 1-$cur_len
	return 0
}

# test produce bh pwd, from ssid and mac md5sum
xor_sum()
{
	local s1=`echo "$1" | md5sum | awk '{print $1}'`
	local s2=`echo "$2" | md5sum | awk '{print $1}'`
	local str=""

	#local len=$(($l1 > $l2 ? $l1 : $l2))
	local len=${#s1}
	for i in `seq 0 2 $((len - 1))`; do
		bb=$((0x${s1:$i:2} ^ 0x${s2:$i:2}))
		#echo bb=$bb
		str="${str}`printf %02x $bb`"
	done
	#echo -n "${str// /}"
	echo -n "${str}"
}

led_link_good()
{
	#rm temporarily because no definition led
	echo "link good"
}

led_link_poor()
{
	#rm temporarily because no definition led
	echo "link poor"
}

led_link_fail()
{
	#rm temporarily because no definition led
	echo "link good"
}

