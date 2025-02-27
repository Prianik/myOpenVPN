#!/bin/bash

# Путь к файлу со списком пользователей
USER_LIST="/etc/openvpn/cmd/user-vpn.txt"
# Логирование
LOG_FILE="/var/log/openvpn/client-connect.log"
# Получаем Common Name (имя пользователя) из переменной окружения
CLIENT_NAME="$common_name"

# Проверяем, существует ли файл со списком пользователей
if [ ! -f "$USER_LIST" ]; then
    echo "Файл $USER_LIST не найден!"
    exit 1  # Блокируем подключение, если файл отсутствует
fi

# Ищем пользователя в файле
USER_STATUS=$(grep "^$CLIENT_NAME " "$USER_LIST" | awk '{print $2}')

# Если пользователь не найден, блокируем подключение
if [ -z "$USER_STATUS" ]; then
	echo -e "$(date +%Y-%m-%d) $(date +%H:%M:%S) $common_name $trusted_ip ---> $ifconfig_pool_remote_ip BLOCK $script_type $bytes_received $bytes_send"  >> "$LOG_FILE"
    echo "$(date): Пользователь $CLIENT_NAME не найден в списке. Блокировка."
    exit 1
fi

# Проверяем статус пользователя
if [ "$USER_STATUS" -eq 1 ]; then
    echo "$(date +%Y-%m-%d) $(date +%H:%M:%S) $common_name $trusted_ip ---> $ifconfig_pool_remote_ip UP $script_type $bytes_received $bytes_send" >> "$LOG_FILE"
    exit 0  # Разрешаем подключение
else
        echo -e "$(date +%Y-%m-%d) $(date +%H:%M:%S) $common_name $trusted_ip ---> $ifconfig_pool_remote_ip BLOCK $script_type $bytes_received $bytes_send"  >> "$LOG_FILE"
	echo "$(date): Пользователь $CLIENT_NAME отключен. Блокировка."
	exit 1  # Блокируем подключение
fi
