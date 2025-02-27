#!/bin/bash

# Путь к файлу index.txt
INDEX_FILE="/etc/openvpn/easy-rsa/pki/index.txt"
# Путь к файлу user-vpn.txt
USER_VPN_FILE="/etc/openvpn/cmd/user-vpn.txt"
ServerDir=/etc/openvpn
homeDir=${ServerDir}/_OpenVPN_KEY
CCD=$(cat ${ServerDir}/server.conf  | grep client-config-dir | awk '{print $2}')
STATUSLOG=$(cat ${ServerDir}/server.conf  | grep ^status | awk '{print $2}')
CLIENTCONECT=/var/log/openvpn/client-connect.log

echo "" >>  $CLIENTCONECT
chmod  666  $CLIENTCONECT
chmod  666 $STATUSLOG

# Резервная копия и Очистка файла user-vpn.txt (если он уже существует)
if [  -f "$USER_VPN_FILE" ]; then
	cp "$USER_VPN_FILE" "$USER_VPN_FILE.bak"
	> "$USER_VPN_FILE"
fi

# Парсинг index.txt
while read -r line; do
    # Извлекаем статус сертификата (первый символ строки)
    STATUS="${line:0:1}"

    # Если статус не "V", пропускаем этого пользователя
    if [ "$STATUS" != "V" ]; then
        continue
    fi

    # Извлекаем Common Name (CN) из Distinguished Name (DN)
    CN=$(echo "$line" | grep -oP 'CN=\K[^/]+')

    # Записываем пользователя в файл user-vpn.txt со статусом 1 (активен)
    echo "$CN 1" >> "$USER_VPN_FILE"
done < "$INDEX_FILE"

# удаляю пустые строки
sed -i '/^$/d' "$USER_VPN_FILE"
sed -i '/^$/d' "$CLIENTCONECT"

# Сортировка файла user-vpn.txt по возрастанию
sort -o "$USER_VPN_FILE" "$USER_VPN_FILE"
chmod  666 "$USER_VPN_FILE"
echo "Файл $USER_VPN_FILE успешно создан."

if [ ! -f "${ServerDir}/firma.txt" ]; then
	read -rp "Enter the company name: " FIRMA
        echo "${FIRMA}" >  "${ServerDir}/firma.txt"
	echo "File  ${ServerDir}/firma.txt create"
fi
