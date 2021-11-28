#!/bin/sh

if [ -f /proc/sys/vm/compact_memory ]
then
	echo 1 > /proc/sys/vm/compact_memory
fi
