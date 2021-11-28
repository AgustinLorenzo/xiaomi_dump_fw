#!/bin/sh
#

# R3600 upgrade file

. /lib/upgrade/common.sh
. /lib/upgrade/libupgrade.sh

klogger() {
    local msg1="$1"
    local msg2="$2"

    if [ "$msg1" = "-n" ]; then
        echo -n "$msg2" >> /dev/kmsg 2>/dev/null
        echo -n "$msg2"
    else
        echo "$msg1" >> /dev/kmsg 2>/dev/null
        echo "$msg1"
    fi  

    return 0
}

board_prepare_upgrade() {
    # gently stop pppd, let it close pppoe session
    ifdown wan
    timeout=5
    while [ $timeout -gt 0 ]; do
        pidof pppd >/dev/null || break
        sleep 1
        let timeout=timeout-1
    done

    # down backhauls
    #ifconfig eth3 down
    #ifconfig wl01 down
    #ifconfig wl11 down

    # clean up upgrading environment
    # call shutdown scripts with some exceptions
    wait_stat=0
    klogger "@Shutdown service "
    for i in /etc/rc.d/K*; do
        # filter out K01reboot-wdt and K99umount

        case $i in
            *reboot-wdt | *umount)
                klogger "$i skipped"
                continue
            ;;
        esac

        [ -x "$i" ] || continue

        # wait for high-priority K* scripts to finish
        if echo "$i" | grep -qE "K7"; then
            if [ $wait_stat -eq 0 ]; then
                wait
                sleep 2
                wait_stat=1
            fi
            klogger "  service $i shutdown 2>&1"
            $i shutdown 2>&1
        else
            klogger "  service $i shutdown 2>&1 &"
            $i shutdown 2>&1 &
        fi
    done

    # try to kill all userspace processes
    # at this point the process tree should look like
    # init(1)---sh(***)---flash.sh(***)
    klogger "@Killing user process "
    for i in $(ps w | grep -v "flash.sh" | grep -v "/bin/ash" | grep -v "PID" | grep -v watchdog | awk '{print $1}'); do
        if [ $i -gt 100 ]; then
            # skip if kthread
            [ -f "/proc/${i}/cmdline" ] || continue

            [ -z "`cat /proc/${i}/cmdline`" ] && {
                klogger " $i is kthread, skip"
                continue
            }
            klogger " kill user process {`ps -w | grep $i | grep -v grep`} "
            kill $i 2>/dev/null
            # TODO: Revert to SIGKILL after watchdog bug is fixed
            # kill -9 $i 2>/dev/null
        fi
    done

    # flush cache and dump meminfo
    sync
    echo 3>/proc/sys/vm/drop_caches
    klogger "@dump meminfo"
    klogger "`cat /proc/meminfo | xargs`"
}

board_start_upgrade_led() {
	gpio 1 1
	gpio 3 1
	gpio l 1000 2
}

board_system_upgrade() {
    local filename=$1
    uboot_mtd=$(grep '"0:APPSBL"' /proc/mtd | awk -F: '{print substr($1,4)}')
    crash_mtd=$(grep '"crash"' /proc/mtd | awk -F: '{print substr($1,4)}')
    #kernel0_mtd=$(grep '"kernel0"' /proc/mtd | awk -F: '{print substr($1,4)}')
    #kernel1_mtd=$(grep '"kernel1"' /proc/mtd | awk -F: '{print substr($1,4)}')
    rootfs0_mtd=$(grep '"rootfs"' /proc/mtd | awk -F: '{print substr($1,4)}')
    rootfs1_mtd=$(grep '"rootfs_1"' /proc/mtd | awk -F: '{print substr($1,4)}')

    os_idx=$(nvram get flag_boot_rootfs)
    rootfs_mtd_current=$(($rootfs0_mtd+${os_idx:-0}))
    rootfs_mtd_target=$(($rootfs0_mtd+$rootfs1_mtd-$rootfs_mtd_current))
    #kernel_mtd_current=$(($rootfs_mtd_current-2))
    #kernel_mtd_target=$(($kernel0_mtd+$kernel1_mtd-$kernel_mtd_current))

    pipe_upgrade_uboot $uboot_mtd $filename
    #pipe_upgrade_kernel $kernel_mtd_target $filename
    pipe_upgrade_rootfs_ubi $rootfs_mtd_target $filename

    # back up etc
    rm -rf /data/etc_bak
    cp -prf /etc /data/etc_bak
}
