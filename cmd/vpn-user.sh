#!/bin/sh

cat /var/log/openvpn/status.log | \
awk '/^10./' | \
awk -F"," '{print $2"\t"$3"\t"$1"\t"$4} ' | \
sort | \
awk '{print $1,$3,$2,$6,$5"/"$4"/"$7} ' | \
column -c 3 -t | \
grep "$1"
