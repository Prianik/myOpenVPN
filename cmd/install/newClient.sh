#!/bin/bash

# shellcheck disable=SC1091,SC2164,SC2034,SC1072,SC1073,SC1009
# Secure OpenVPN server installer for Debian, Ubuntu, CentOS, Amazon Linux 2, Fedora, Oracle Linux 8, Arch Linux, Rocky Linux and AlmaLinux.
# https://github.com/angristan/openvpn-install


ServerDir=/etc/openvpn
USER_VPN_FILE="/etc/openvpn/cmd/user-vpn.txt"
homeDir=${ServerDir}/_OpenVPN_KEY
CCD=$(cat ${ServerDir}/server.conf  | grep client-config-dir | awk '{print $2}')
PASS=1
CLIENT=$1

echo ""
echo "Tell me a name for the client."
echo "The name must consist of alphanumeric character. It may also include an underscore or a dash."
until [[ $CLIENT =~ ^[a-zA-Z0-9._-]+$ ]]; do
	read -rp "Client name: " -e CLIENT
done

if [ ! -d "${homeDir}" ]; then
        mkdir ${homeDir}
fi

CLIENTEXISTS=$(tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt | grep -c -E "/CN=$CLIENT\$")
if [[ $CLIENTEXISTS == '1' ]]; then
	echo ""
	echo "The specified client CN was already found in easy-rsa, please choose another name."
	exit
else
	cd /etc/openvpn/easy-rsa/ || return
	case $PASS in
	1)
		EASYRSA_CERT_EXPIRE=3650 ./easyrsa --batch build-client-full "$CLIENT" nopass
		;;
	2)
		echo "⚠️ You will be asked for the client password below ⚠️"
		EASYRSA_CERT_EXPIRE=3650 ./easyrsa --batch build-client-full "$CLIENT"
		;;
	esac
		echo "Client $CLIENT added."
fi

# Determine if we use tls-auth or tls-crypt
if grep -qs "^tls-crypt" /etc/openvpn/server.conf; then
	TLS_SIG="1"
elif grep -qs "^tls-auth" /etc/openvpn/server.conf; then
	TLS_SIG="2"
fi

# Generates the custom client.ovpn
cp /etc/openvpn/client-template.txt "$homeDir/$CLIENT.ovpn"
{
	echo "<ca>"
	cat "/etc/openvpn/easy-rsa/pki/ca.crt"
	echo "</ca>"

	echo "<cert>"
	awk '/BEGIN/,/END CERTIFICATE/' "/etc/openvpn/easy-rsa/pki/issued/$CLIENT.crt"
	echo "</cert>"
	
 	echo "<key>"
	cat "/etc/openvpn/easy-rsa/pki/private/$CLIENT.key"
	echo "</key>"

	case $TLS_SIG in
	1)
		echo "<tls-crypt>"
		cat /etc/openvpn/tls-crypt.key
		echo "</tls-crypt>"
		;;
	2)
		echo "key-direction 1"
		echo "<tls-auth>"
		cat /etc/openvpn/tls-auth.key
		echo "</tls-auth>"
		;;
	esac
} >>"$homeDir/$CLIENT.ovpn"

echo ""
echo "The configuration file has been written to $homeDir/$CLIENT.ovpn."
echo "Download the .ovpn file and import it in your OpenVPN client."

echo "------------------------------------------------------------------------------"
echo "$CLIENT 1" >>  "$USER_VPN_FILE"

# удаляю пустые строки
sed -i '/^$/d' "$USER_VPN_FILE"

# Сортировка файла user-vpn.txt по возрастанию
sort -o "$USER_VPN_FILE" "$USER_VPN_FILE"

echo ...Copy _default CCD to $CLIENT .........
cp $CCD/_default /$CCD/$CLIENT
cat $CCD/$CLIENT
echo "------------------------------------------------------------------------------"
