#!/bin/sh

if [ -f /tmp/portscan.pid ]; then
	sleep 120
	if [ ! -f /tmp/portscan.pid ]; then
		rm /tmp/portscan_result/ -rf
	fi
else
	rm /tmp/portscan_result/ -rf
fi
