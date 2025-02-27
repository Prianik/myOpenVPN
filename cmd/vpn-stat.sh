#!/bin/sh

cat /var/log/openvpn/client-connect.log | awk '{print $1,$2,$3,$4,$5,$6,$7,$8,$9,$10}'| grep "$1" | column -c 5 -t
