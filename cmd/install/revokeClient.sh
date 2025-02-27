#!/bin/bash

# --------------------------------------------------------------------
# Описание: Скрипт для отзыва сертификата клиента OpenVPN
# Источник: Основано на https://github.com/angristan/openvpn-install
# Автор: Grok 3 (xAI), отформатировано и прокомментировано 27.02.2025
# Зависимости: bash, awk, grep, sed, sort, easy-rsa
# --------------------------------------------------------------------

# Отключаем некоторые предупреждения shellcheck для совместимости с оригинальным скриптом
# shellcheck disable=SC1091,SC2164,SC2034,SC1072,SC1073,SC1009

# Определение путей и переменных
SERVER_DIR="/etc/openvpn"                         # Основная директория OpenVPN
USER_VPN_FILE="${SERVER_DIR}/cmd/user-vpn.txt"    # Файл со списком активных VPN-пользователей
HOME_DIR="${SERVER_DIR}/_OpenVPN_KEY"             # Директория для хранения ключей и .ovpn файлов
CCD=$(grep "client-config-dir" "${SERVER_DIR}/server.conf" | awk '{print $2}')  # Путь к client-config-dir
INDEX_FILE="${SERVER_DIR}/easy-rsa/pki/index.txt" # Файл индекса сертификатов
PASS=1                                            # Не используется в этом скрипте, оставлено для совместимости
CLIENT="${1}"                                     # Имя клиента из аргумента командной строки (опционально)

# Проверка на наличие server.conf
if [ ! -f "${SERVER_DIR}/server.conf" ]; then
    echo "Ошибка: Файл ${SERVER_DIR}/server.conf не найден."
    exit 1
fi

# Проверка на наличие index.txt
if [ ! -f "${INDEX_FILE}" ]; then
    echo "Ошибка: Файл ${INDEX_FILE} не найден."
    exit 1
fi

# Подсчет количества активных клиентов
NUMBER_OF_CLIENTS=$(tail -n +2 "${INDEX_FILE}" | grep -c "^V")
if [ "${NUMBER_OF_CLIENTS}" -eq 0 ]; then
    echo ""
    echo "У вас нет существующих клиентов!"
    exit 1
fi

# Вывод списка активных клиентов и выбор для отзыва
echo ""
echo "Выберите сертификат клиента для отзыва:"
tail -n +2 "${INDEX_FILE}" | grep "^V" | cut -d '=' -f 2 | nl -s ') '

until [[ "${CLIENTNUMBER}" -ge 1 && "${CLIENTNUMBER}" -le "${NUMBER_OF_CLIENTS}" ]]; do
    if [ "${NUMBER_OF_CLIENTS}" -eq 1 ]; then
        read -rp "Выберите клиента [1]: " CLIENTNUMBER
    else
        read -rp "Выберите клиента [1-${NUMBER_OF_CLIENTS}]: " CLIENTNUMBER
    fi
done

# Извлечение имени клиента по номеру
CLIENT=$(tail -n +2 "${INDEX_FILE}" | grep "^V" | cut -d '=' -f 2 | sed -n "${CLIENTNUMBER}p")

# Переход в директорию easy-rsa для работы с сертификатами
cd "${SERVER_DIR}/easy-rsa/" || { echo "Ошибка: Не удалось перейти в ${SERVER_DIR}/easy-rsa/"; exit 1; }

# Отзыв сертификата клиента
./easyrsa --batch revoke "${CLIENT}" || {
    echo "Ошибка: Не удалось отозвать сертификат для ${CLIENT}";
    exit 1;
}

# Генерация нового CRL (Certificate Revocation List)
EASYRSA_CRL_DAYS=3650 ./easyrsa gen-crl || {
    echo "Ошибка: Не удалось сгенерировать CRL";
    exit 1;
}

# Обновление файла crl.pem на сервере
rm -f "${SERVER_DIR}/crl.pem" || { echo "Ошибка: Не удалось удалить старый ${SERVER_DIR}/crl.pem"; exit 1; }
cp "${SERVER_DIR}/easy-rsa/pki/crl.pem" "${SERVER_DIR}/crl.pem" || {
    echo "Ошибка: Не удалось скопировать новый crl.pem";
    exit 1;
}
chmod 644 "${SERVER_DIR}/crl.pem"  # Установка прав rw-r--r--

# Удаление файлов клиента
find /home/ -maxdepth 2 -name "${CLIENT}.ovpn" -delete 2>/dev/null
rm -f "/root/${CLIENT}.ovpn" 2>/dev/null
rm -f "${HOME_DIR}/${CLIENT}.ovpn" 2>/dev/null
rm -f "${CCD}/${CLIENT}" 2>/dev/null

# Удаление записи клиента из ipp.txt
if [ -f "${SERVER_DIR}/ipp.txt" ]; then
    sed -i "/^${CLIENT},.*/d" "${SERVER_DIR}/ipp.txt" || {
        echo "Ошибка: Не удалось обновить ${SERVER_DIR}/ipp.txt";
        exit 1;
    }
fi

# Создание резервной копии index.txt
cp "${INDEX_FILE}" "${INDEX_FILE}.bk" || {
    echo "Ошибка: Не удалось создать резервную копию ${INDEX_FILE}";
    exit 1;
}

# Удаление клиента из user-vpn.txt
if [ -f "${USER_VPN_FILE}" ]; then
    sed -i "/^${CLIENT}.*/d" "${USER_VPN_FILE}" || {
        echo "Ошибка: Не удалось обновить ${USER_VPN_FILE}";
        exit 1;
    }

    # Удаление пустых строк
    sed -i '/^$/d' "${USER_VPN_FILE}" || {
        echo "Ошибка: Не удалось удалить пустые строки из ${USER_VPN_FILE}";
        exit 1;
    }

    # Сортировка файла user-vpn.txt
    sort -o "${USER_VPN_FILE}" "${USER_VPN_FILE}" || {
        echo "Ошибка: Не удалось отсортировать ${USER_VPN_FILE}";
        exit 1;
    }
fi

# Успешное завершение
echo ""
echo "Сертификат клиента ${CLIENT} успешно отозван."
exit 0
