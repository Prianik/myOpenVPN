#!/bin/bash

# Отключаем некоторые предупреждения shellcheck для совместимости с оригинальным скриптом
# shellcheck disable=SC1091,SC2164,SC2034,SC1072,SC1073,SC1009

# Определение путей и переменных
SERVER_DIR="/etc/openvpn"                         # Основная директория OpenVPN
USER_VPN_FILE="${SERVER_DIR}/cmd/user-vpn.txt"    # Файл со списком активных VPN-пользователей
HOME_DIR="${SERVER_DIR}/_OpenVPN_KEY"             # Директория для хранения ключей и .ovpn файлов
CCD=$(grep "client-config-dir" "${SERVER_DIR}/server.conf" | awk '{print $2}')  # Путь к client-config-dir
PASS=1                                            # По умолчанию сертификат без пароля
CLIENT="$1"                                       # Имя клиента из аргумента командной строки
RDP=$2
CERT_EXPIRE=3650

# Проверка на наличие server.conf
if [ ! -f "${SERVER_DIR}/server.conf" ]; then
    echo "Ошибка: Файл ${SERVER_DIR}/server.conf не найден."
    exit 1
fi

# Запрос имени клиента, если не указано в аргументах
echo ""
echo "Укажите имя для клиента."
echo "Имя должно состоять из букв, цифр, символов '_' или '-'."
until [[ "${CLIENT}" =~ ^[a-zA-Z0-9._-]+$ ]]; do
    read -rp "Имя клиента: " -e CLIENT
    read -rp "RDP user: " -e RDP
done

# Создание директории для ключей, если её нет
if [ ! -d "${HOME_DIR}" ]; then
    mkdir -p "${HOME_DIR}" || { echo "Ошибка: Не удалось создать директорию ${HOME_DIR}"; exit 1; }
fi

# Проверка на существование клиента в easy-rsa
CLIENT_EXISTS=$(tail -n +2 "${SERVER_DIR}/easy-rsa/pki/index.txt" | grep -c -E "/CN=${CLIENT}\$")
if [ "${CLIENT_EXISTS}" -eq 1 ]; then
    echo ""
    echo "Ошибка: Клиент с именем ${CLIENT} уже существует в easy-rsa. Выберите другое имя."
    exit 1
fi

# Генерация сертификата клиента
cd "${SERVER_DIR}/easy-rsa/" || { echo "Ошибка: Не удалось перейти в ${SERVER_DIR}/easy-rsa/"; exit 1; }
case "${PASS}" in
    1)
        EASYRSA_CERT_EXPIRE=3650 ./easyrsa --batch build-client-full "${CLIENT}" nopass || {
            echo "Ошибка: Не удалось создать сертификат для ${CLIENT}";
            exit 1;
        }
        ;;
    2)
        echo "⚠️ Вам будет предложено ввести пароль для клиента ниже ⚠️"
        EASYRSA_CERT_EXPIRE=3650 ./easyrsa --batch build-client-full "${CLIENT}" || {
            echo "Ошибка: Не удалось создать сертификат для ${CLIENT}";
            exit 1;
        }
        ;;
esac
echo "Клиент ${CLIENT} успешно добавлен."

# Определение типа TLS (tls-auth или tls-crypt)
if grep -qs "^tls-crypt" "${SERVER_DIR}/server.conf"; then
    TLS_SIG="1"
elif grep -qs "^tls-auth" "${SERVER_DIR}/server.conf"; then
    TLS_SIG="2"
fi

# Генерация конфигурационного файла .ovpn для клиента
OVPN_FILE="${HOME_DIR}/${CLIENT}.ovpn"

if [ ! -f "${SERVER_DIR}/client-template.txt" ]; then
    echo "Ошибка: Шаблон ${SERVER_DIR}/client-template.txt не найден."
    exit 1
fi

echo "#" > "${OVPN_FILE}"
echo "#---$CLIENT----$RDP--" >> "${OVPN_FILE}"
echo "#" >> "${OVPN_FILE}"
cat /etc/openvpn/client-template.txt >>  "${OVPN_FILE}"
{
    echo "<ca>"
    cat "${SERVER_DIR}/easy-rsa/pki/ca.crt" || { echo "Ошибка: Не удалось прочитать ca.crt"; exit 1; }
    echo "</ca>"

    echo "<cert>"
    awk '/BEGIN/,/END CERTIFICATE/' "${SERVER_DIR}/easy-rsa/pki/issued/${CLIENT}.crt" || {
        echo "Ошибка: Не удалось извлечь сертификат ${CLIENT}.crt";
        exit 1;
    }
    echo "</cert>"

    echo "<key>"
    cat "${SERVER_DIR}/easy-rsa/pki/private/${CLIENT}.key" || {
        echo "Ошибка: Не удалось прочитать ключ ${CLIENT}.key";
        exit 1;
    }
    echo "</key>"

    case "${TLS_SIG}" in
        1)
            echo "<tls-crypt>"
            cat "${SERVER_DIR}/tls-crypt.key" || { echo "Ошибка: Не удалось прочитать tls-crypt.key"; exit 1; }
            echo "</tls-crypt>"
            ;;
        2)
            echo "key-direction 1"
            echo "<tls-auth>"
            cat "${SERVER_DIR}/tls-auth.key" || { echo "Ошибка: Не удалось прочитать tls-auth.key"; exit 1; }
            echo "</tls-auth>"
            ;;
    esac
} >> "${OVPN_FILE}"

echo ""
echo "Конфигурационный файл записан в ${OVPN_FILE}."
echo "Скачайте файл .ovpn и импортируйте его в ваш OpenVPN-клиент."

# Добавление клиента в список активных пользователей
echo "------------------------------------------------------------------------------"
echo "${CLIENT} 1" >> "${USER_VPN_FILE}" || { echo "Ошибка записи в ${USER_VPN_FILE}"; exit 1; }

# Удаление пустых строк из user-vpn.txt
sed -i '/^$/d' "${USER_VPN_FILE}" || { echo "Ошибка обработки ${USER_VPN_FILE}"; exit 1; }

# Сортировка файла user-vpn.txt
sort -o "${USER_VPN_FILE}" "${USER_VPN_FILE}" || { echo "Ошибка сортировки ${USER_VPN_FILE}"; exit 1; }

# Копирование стандартной конфигурации CCD для клиента
echo "...Копирование _default CCD для ${CLIENT}..."
if [ -f "${CCD}/_default" ]; then
    cp "${CCD}/_default" "${CCD}/${CLIENT}" || {
        echo "Ошибка: Не удалось скопировать _default в ${CCD}/${CLIENT}";
        exit 1;
    }
    cat "${CCD}/${CLIENT}"
else
    echo "Предупреждение: Файл ${CCD}/_default не найден, CCD для ${CLIENT} не создан."
fi
echo "------------------------------------------------------------------------------"

# Успешное завершение
echo "Скрипт успешно выполнен."
exit 0
