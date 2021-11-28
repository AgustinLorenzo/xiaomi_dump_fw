#!/bin/ash
echo "call miot_post " >> /dev/console
if [ -n "$3" ]; then
	iotrelay -t 0 -m $1 -o $2 -I $3 &
else
	iotrelay -t 0 -m $1 -I $2 &
fi
