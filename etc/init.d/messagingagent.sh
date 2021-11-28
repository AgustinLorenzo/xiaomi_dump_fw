#!/bin/sh /etc/rc.common

START=49

USE_PROCD=1
PROG=/usr/bin/messagingagent

num='2'
config_load misc
config_get num messagingagent thread_num

start_service() {
	# start command
	procd_open_instance
	procd_set_param command "$PROG" --handler_threads "$num"
	procd_set_param respawn
	procd_close_instance
	echo "start messagingagent ok."
}
