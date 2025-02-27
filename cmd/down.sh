#!/bin/bash


#chmod 777 /var/log/openvpn/client-connect.log

echo -e "$(date +%Y-%m-%d) $(date +%H:%M:%S) $common_name $trusted_ip <--- $ifconfig_pool_remote_ip DOWN $script_type $bytes_received $bytes_send"   >> /var/log/openvpn/client-connect.log
exit 0
