#!/bin/sh

#echo "Date Time Name IP1 --  IP2  TYPE TYPE2 RECIVE SEND" | awk '{print $1,$2,$3,$4,$5,$6,$7,$8,$9,$10}' | column -c 5 -t
cat /var/log/openvpn/client-connect.log | awk '{print $1,$2,$3,$4,$5,$6,$7,$8,$9,$10}'| grep "$1" | column -c 5 -t
