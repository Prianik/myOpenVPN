#!/bin/bash

# --------------------------------------------------------------------
# Описание: Скрипт для управления VPN-пользователями и настройками в Ubuntu
# Автор: Grok 3 (xAI), отформатировано и прокомментировано 27.02.2025
# Зависимости: bash, awk, grep, sed, sort, locale
# --------------------------------------------------------------------

# Определение путей к файлам и директориям
INDEX_FILE="/etc/openvpn/easy-rsa/pki/index.txt"        # Файл индекса сертификатов
USER_VPN_FILE="/etc/openvpn/cmd/user-vpn.txt"           # Файл со списком активных VPN-пользователей
SERVER_DIR="/etc/openvpn"                               # Основная директория OpenVPN
HOME_DIR="${SERVER_DIR}/_OpenVPN_KEY"                   # Директория для ключей
CLIENT_CONNECT="/var/log/openvpn/client-connect.log"    # Лог подключений клиентов

# Извлечение путей из конфигурации сервера
CCD=$(grep "client-config-dir" "${SERVER_DIR}/server.conf" | awk '{print $2}')  # Путь к client-config-dir
STATUS_LOG=$(grep "^status" "${SERVER_DIR}/server.conf" | awk '{print $2}')     # Путь к статус-логу

# Проверка на существование server.conf
if [ ! -f "${SERVER_DIR}/server.conf" ]; then
    echo "Ошибка: Файл ${SERVER_DIR}/server.conf не найден."
    exit 1
fi

# Настройка логов
echo "" >> "${CLIENT_CONNECT}" || { echo "Ошибка записи в ${CLIENT_CONNECT}"; exit 1; }
chmod 666 "${CLIENT_CONNECT}"  # Установка прав rw-rw-rw-
chmod 666 "${STATUS_LOG}"      # Установка прав rw-rw-rw-

# Резервное копирование и очистка user-vpn.txt
if [ -f "${USER_VPN_FILE}" ]; then
    cp "${USER_VPN_FILE}" "${USER_VPN_FILE}.bak" || { echo "Ошибка при создании бэкапа ${USER_VPN_FILE}"; exit 1; }
    > "${USER_VPN_FILE}" || { echo "Ошибка при очистке ${USER_VPN_FILE}"; exit 1; }
fi

# Парсинг файла index.txt для получения активных пользователей
if [ ! -f "${INDEX_FILE}" ]; then
    echo "Ошибка: Файл ${INDEX_FILE} не найден."
    exit 1
fi

while read -r line; do
    # Извлекаем статус сертификата (первый символ строки)
    STATUS="${line:0:1}"

    # Пропускаем, если сертификат не действителен (не 'V')
    [ "${STATUS}" != "V" ] && continue

    # Извлекаем Common Name (CN) из строки
    CN=$(echo "${line}" | grep -oP 'CN=\K[^/]+')
    [ -z "${CN}" ] && { echo "Предупреждение: Не удалось извлечь CN из строки: ${line}"; continue; }

    # Записываем пользователя в user-vpn.txt со статусом 1 (активен)
    echo "${CN} 1" >> "${USER_VPN_FILE}" || { echo "Ошибка записи в ${USER_VPN_FILE}"; exit 1; }
done < "${INDEX_FILE}"

# Удаление пустых строк
sed -i '/^$/d' "${USER_VPN_FILE}" || { echo "Ошибка обработки ${USER_VPN_FILE}"; exit 1; }
sed -i '/^$/d' "${CLIENT_CONNECT}" || { echo "Ошибка обработки ${CLIENT_CONNECT}"; exit 1; }

# Сортировка файла user-vpn.txt
sort -o "${USER_VPN_FILE}" "${USER_VPN_FILE}" || { echo "Ошибка сортировки ${USER_VPN_FILE}"; exit 1; }
chmod 666 "${USER_VPN_FILE}"  # Установка прав rw-rw-rw-
echo "Файл ${USER_VPN_FILE} успешно создан."

# Установка названия фирмы для отчетов
if [ ! -f "${SERVER_DIR}/firma.txt" ]; then
    read -rp "Введите название компании: " FIRMA
    echo "${FIRMA}" > "${SERVER_DIR}/firma.txt" || { echo "Ошибка создания ${SERVER_DIR}/firma.txt"; exit 1; }
    echo "Файл ${SERVER_DIR}/firma.txt создан."
fi

# Создание символических ссылок
# Проверяем существование исходных файлов перед созданием ссылок
for script in "newClient.sh" "revokeClient.sh" "vpn-stat.sh" "vpn-user.sh"; do
    case "$script" in
        "vpn-stat.sh")
            SRC="${SERVER_DIR}/cmd/vpn-stat.sh"
            DEST="/usr/local/bin/vpn-stat"
            ;;
        "vpn-user.sh")
            SRC="${SERVER_DIR}/cmd/vpn-user.sh"
            DEST="/usr/local/bin/vpn-user"
            ;;
        *)
            SRC="${SERVER_DIR}/cmd/install/${script}"
            DEST="${SERVER_DIR}/${script%.sh}"
            ;;
    esac

    if [ -f "${SRC}" ]; then
        ln -sf "${SRC}" "${DEST}" || { echo "Ошибка создания ссылки ${DEST}"; exit 1; }
        echo "Создана ссылка: ${DEST} -> ${SRC}"
    else
        echo "Предупреждение: Файл ${SRC} не найден, ссылка не создана."
    fi
done

# Проверка и настройка локали ru_RU.UTF-8
if locale -a | grep -q "ru_RU.utf8"; then
    echo "Локаль ru_RU.UTF-8 уже доступна."
else
    echo "Локаль ru_RU.UTF-8 не найдена, запускаем настройку..."
    sudo dpkg-reconfigure locales || { echo "Ошибка настройки локалей"; exit 1; }
    export LANG="ru_RU.UTF-8"
    echo "Локаль ru_RU.UTF-8 установлена для текущей сессии."
fi

# Успешное завершение
echo "Скрипт выполнен успешно."
exit 0
