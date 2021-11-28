#!/bin/sh

klogger() {
	local msg1="$1"
	local msg2="$2"

	if [ "$msg1" = "-n" ]; then
		echo -n "$msg2" >> /dev/kmsg 2>/dev/null
	else
		echo "$msg1" >> /dev/kmsg 2>/dev/null
	fi

	return 0
}

hndmsg() {
	if [ -n "$msg" ]; then
		echo "$msg"
		echo "$msg" >> /dev/kmsg 2>/dev/null

		echo $log > /proc/sys/kernel/printk
		stty intr ^C
		exit 1
	fi
}

uperr() {
	exit 1
}

pipe_upgrade_generic() {
	local package=$1
	local segment_name=$2
	local mtd_dev=mtd$3
	local ret=0

	mkxqimage -c $package -f $segment_name
	if [ $? -eq 0 ]; then
		klogger -n "Burning $segment_name to $mtd_dev ..."

		exec 9>&1

		local pipestatus0=`( (mkxqimage -x $package -f $segment_name -n || echo $? >&8) | \
			mtd write - /dev/$mtd_dev ) 8>&1 >&9`
		if [ -z "$pipestatus0" -a $? -eq 0 ]; then
			ret=0
		else
			ret=1
		fi
		exec 9>&-
	fi

	return $ret
}

pipe_upgrade_uboot() {
	if [ $1 ]; then
		pipe_upgrade_generic $2 uboot.bin $1
		if [ $? -eq 0 ]; then
			klogger "Done"
		else
			klogger "Error"
			uperr
		fi
	fi
}

pipe_upgrade_crash() {
	if [ $1 ]; then
		pipe_upgrade_generic $2 crash.bin $1
		if [ $? -eq 0 ]; then
			klogger "Done"
		else
			klogger "Error"
			uperr
		fi
	fi
}

pipe_upgrade_kernel() {
	if [ $1 ]; then
		pipe_upgrade_generic $2 uImage.bin $1
		if [ $? -eq 0 ]; then
			klogger "Done"
		else
			klogger "Error"
			uperr
		fi
	fi
}

pipe_upgrade_rootfs_ubi() {
	local mtd_dev=mtd$1
	local package=$2
	local segment_name="root.ubi"

	mkxqimage -c $package -f $segment_name
	if [ $? -eq 0 -a $1 ]; then
		local segment_size=$(mkxqimage -c $package -f $segment_name)
		segment_size=${segment_size##*length = }
		segment_size=${segment_size%%, partition*}

		klogger -n "Burning rootfs image to $mtd_dev ..."

		exec 9>&1
		local pipestatus0=`((mkxqimage -x $package -f $segment_name -n || echo $? >&8) | \
			ubiformat /dev/$mtd_dev -f - -S $((segment_size)) -s 2048 -O 2048 -y) 8>&1 >&9`

		if [ -z "$pipestatus0" -a $? -eq 0 ]; then
			exec 9>&-
			klogger "Done"
		else
			exec 9>&-
			klogger "Error"
			uperr
		fi
	fi
}

upgrade_uboot() {
	local mtd_dev=mtd$1

	if [ -f uboot.bin -a $1 ]; then
		klogger -n "Burning uboot image to $mtd_dev ..."
		mtd write uboot.bin /dev/$mtd_dev
		if [ $? -eq 0 ]; then
			klogger "Done"
		else
			klogger "Error"
			uperr
		fi
	fi
}

upgrade_crash() {
	local mtd_dev=mtd$1

	if [ -f crash.bin -a $1 ]; then
		klogger -n "Burning crash image to $mtd_dev ..."
		mtd write crash.bin /dev/$mtd_dev
		if [ $? -eq 0 ]; then
			klogger "Done"
		else
			klogger "Error"
			uperr
		fi
	fi
}

upgrade_kernel() {
	local mtd_dev=mtd$1

	if [ -f uImage.bin -a $1 ]; then
		klogger -n "Burning kernel image to $mtd_dev ..."
		mtd write uImage.bin /dev/$mtd_dev
		if [ $? -eq 0 ]; then
			klogger "Done"
		else
			klogger "Error"
			uperr
		fi
	fi
}

upgrade_rootfs_ubi() {
	local mtd_dev=mtd$1

	if [ -f root.ubi -a $1 ]; then
		klogger -n "Burning rootfs image to $mtd_dev ..."
		ubiformat /dev/$mtd_dev -f root.ubi -s 2048 -O 2048 -y
		if [ $? -eq 0 ]; then
			klogger "Done"
		else
			klogger "Error"
			uperr
		fi
	fi
}

verify_rootfs_ubifs() {
	local mtd_devn=$1
	local temp_ubi_data_devn=9
	klogger "Check if mtd$mtd_devn can be attached as an ubi device ..."
	# Try attach the device
	ubiattach /dev/ubi_ctrl -d $temp_ubi_data_devn -m $mtd_devn -O 2048
	if [ "$?" == "0" ]; then
		klogger "PASSED"
		ubidetach -d $temp_ubi_data_devn
		return 0
	else
		klogger "FAILED"
		return 1
	fi
}

# $1=mtd device name
# $2=src file name
upgrade_mtd_generic() {
	local mtd_dev="$1"
	local src_file="$2"

	if [ -f "$src_file" -a $mtd_dev ]; then
		klogger -n "Burning "$src_file" to $mtd_dev ..."
		mtd write "$src_file" $mtd_dev
		if [ $? -eq 0 ]; then
			klogger "Done"
		else
			klogger "Error"
			uperr
		fi
	fi
}

# $1=mtd device name
# $2=src file name
upgrade_mtd_ubi() {
	local mtd_dev="$1"
	local src_file="$2"
	local mtd_node="$(grep $mtd_dev /proc/mtd | awk -F: '{print $1}')"

	if [ -f "$src_file" -a $mtd_dev ]; then
		klogger -n "Burning "$src_file" to $mtd_dev ..."
		ubiformat /dev/$mtd_node -f "$src_file" -s 2048 -O 2048 -y
		if [ $? -eq 0 ]; then
			klogger "Done"
		else
			klogger "Error"
			uperr
		fi
	fi
}
