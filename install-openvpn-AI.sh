#!/bin/bash

# --------------------------------------------------------------------
# Описание: Установочный скрипт OpenVPN для различных дистрибутивов Linux
# Источник: https://github.com/angristan/openvpn-install
# Автор: Grok 3 (xAI), отформатировано и прокомментировано 27.02.2025
# Зависимости: bash, curl, wget, openvpn, easy-rsa, iptables, systemd
# --------------------------------------------------------------------

# Отключаем некоторые предупреждения shellcheck для совместимости с оригинальным скриптом
# shellcheck disable=SC1091,SC2164,SC2034,SC1072,SC1073,SC1009

# Базовый IP-адрес для VPN-сети
IPVPN="10.91.0"

# Функция проверки запуска от имени root
function isRoot() {
    if [ "$EUID" -ne 0 ]; then
        echo "Ошибка: Скрипт должен выполняться от имени root."
        return 1
    fi
}

# Функция проверки наличия TUN-устройства
function tunAvailable() {
    if [ ! -e /dev/net/tun ]; then
        echo "Ошибка: TUN-устройство не доступно."
        return 1
    fi
}

# Функция определения операционной системы
function checkOS() {
    if [[ -e /etc/debian_version ]]; then
        OS="debian"
        source /etc/os-release
        if [[ "$ID" == "debian" || "$ID" == "raspbian" ]]; then
            if [[ "$VERSION_ID" -lt 9 ]]; then
                echo "⚠️ Ваша версия Debian не поддерживается (требуется >= 9)."
                until [[ "$CONTINUE" =~ (y|n) ]]; do
                    read -rp "Продолжить на свой риск? [y/n]: " -e CONTINUE
                done
                [[ "$CONTINUE" == "n" ]] && exit 1
            fi
        elif [[ "$ID" == "ubuntu" ]]; then
            OS="ubuntu"
            MAJOR_UBUNTU_VERSION=$(echo "$VERSION_ID" | cut -d '.' -f1)
            if [[ "$MAJOR_UBUNTU_VERSION" -lt 16 ]]; then
                echo "⚠️ Ваша версия Ubuntu не поддерживается (требуется >= 16.04)."
                until [[ "$CONTINUE" =~ (y|n) ]]; do
                    read -rp "Продолжить на свой риск? [y/n]: " -e CONTINUE
                done
                [[ "$CONTINUE" == "n" ]] && exit 1
            fi
        fi
    elif [[ -e /etc/system-release ]]; then
        source /etc/os-release
        case "$ID" in
            "fedora" | "fedora"*) OS="fedora" ;;
            "centos" | "rocky" | "almalinux")
                OS="centos"
                if [[ ${VERSION_ID%.*} -lt 7 ]]; then
                    echo "Ошибка: Поддерживаются только CentOS 7 и 8."
                    exit 1
                fi
                ;;
            "ol")
                OS="oracle"
                if [[ ! "$VERSION_ID" =~ (8) ]]; then
                    echo "Ошибка: Поддерживается только Oracle Linux 8."
                    exit 1
                fi
                ;;
            "amzn")
                OS="amzn"
                if [[ "$VERSION_ID" != "2" ]]; then
                    echo "Ошибка: Поддерживается только Amazon Linux 2."
                    exit 1
                fi
                ;;
        esac
    elif [[ -e /etc/arch-release ]]; then
        OS="arch"
    else
        echo "Ошибка: Система не поддерживается скриптом."
        exit 1
    fi
}

# Функция начальной проверки
function initialCheck() {
    isRoot || exit 1
    tunAvailable || exit 1
    checkOS
}

# Функция запроса параметров установки
function installQuestions() {
    echo "Добро пожаловать в установщик OpenVPN!"
    echo "Репозиторий: https://github.com/Prianik/myOpenVPN"
    echo ""

    echo "Перед началом установки нужно ответить на несколько вопросов."
    echo "Нажмите Enter для принятия значений по умолчанию."
    echo ""

    # Запрос IP-адреса для OpenVPN
    echo "Укажите IPv4-адрес интерфейса, на котором будет работать OpenVPN."
    IP=$(ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | head -1)
    [[ -z "$IP" ]] && IP=$(ip -6 addr | sed -ne 's|^.* inet6 \([^/]*\)/.* scope global.*$|\1|p' | head -1)
    APPROVE_IP=${APPROVE_IP:-n}
    if [[ "$APPROVE_IP" =~ n ]]; then
        read -rp "IP-адрес: " -e -i "$IP" IP
    fi

    # Проверка NAT
    if echo "$IP" | grep -qE '^(10\.|172\.1[6789]\.|172\.2[0-9]\.|172\.3[01]\.|192\.168)'; then
        echo "Сервер находится за NAT. Укажите публичный IPv4 или hostname."
        PUBLICIP=$(curl -s https://api.ipify.org)
        until [[ -n "$ENDPOINT" ]]; do
            read -rp "Публичный IPv4 или hostname: " -e -i "$PUBLICIP" ENDPOINT
        done
    fi

    # Проверка IPv6
    echo ""
    echo "Проверка поддержки IPv6..."
    if type ping6 >/dev/null 2>&1; then
        PING6="ping6 -c3 ipv6.google.com > /dev/null 2>&1"
    else
        PING6="ping -6 -c3 ipv6.google.com > /dev/null 2>&1"
    fi
    if eval "$PING6"; then
        echo "Ваш сервер поддерживает IPv6."
        SUGGESTION="y"
    else
        echo "IPv6 не поддерживается."
        SUGGESTION="n"
    fi
    until [[ "$IPV6_SUPPORT" =~ (y|n) ]]; do
        read -rp "Включить IPv6 (NAT)? [y/n]: " -e -i "$SUGGESTION" IPV6_SUPPORT
    done

    # Выбор порта
    echo ""
    echo "Какой порт использовать для OpenVPN?"
    echo "   1) По умолчанию: 1194"
    echo "   2) Пользовательский"
    echo "   3) Случайный [49152-65535]"
    until [[ "$PORT_CHOICE" =~ ^[1-3]$ ]]; do
        read -rp "Выбор порта [1-3]: " -e -i 1 PORT_CHOICE
    done
    case "$PORT_CHOICE" in
        1) PORT="1194" ;;
        2)
            until [[ "$PORT" =~ ^[0-9]+$ && "$PORT" -ge 1 && "$PORT" -le 65535 ]]; do
                read -rp "Пользовательский порт [1-65535]: " -e -i 1194 PORT
            done
            ;;
        3)
            PORT=$(shuf -i49152-65535 -n1)
            echo "Случайный порт: $PORT"
            ;;
    esac

    # Выбор протокола
    echo ""
    echo "Какой протокол использовать?"
    echo "UDP быстрее, используйте TCP только если UDP недоступен."
    until [[ "$PROTOCOL_CHOICE" =~ ^[1-2]$ ]]; do
        read -rp "Протокол [1-UDP, 2-TCP]: " -e -i 1 PROTOCOL_CHOICE
    done
    case "$PROTOCOL_CHOICE" in
        1) PROTOCOL="udp" ;;
        2) PROTOCOL="tcp" ;;
    esac

    # Настройка сжатия
    echo ""
    echo "Включить сжатие? Не рекомендуется из-за атаки VORACLE."
    until [[ "$COMPRESSION_ENABLED" =~ (y|n) ]]; do
        read -rp "Включить сжатие? [y/n]: " -e -i n COMPRESSION_ENABLED
    done
    if [[ "$COMPRESSION_ENABLED" == "y" ]]; then
        echo "Выберите алгоритм сжатия:"
        echo "   1) LZ4-v2"
        echo "   2) LZ4"
        echo "   3) LZO"
        until [[ "$COMPRESSION_CHOICE" =~ ^[1-3]$ ]]; do
            read -rp "Алгоритм сжатия [1-3]: " -e -i 1 COMPRESSION_CHOICE
        done
        case "$COMPRESSION_CHOICE" in
            1) COMPRESSION_ALG="lz4-v2" ;;
            2) COMPRESSION_ALG="lz4" ;;
            3) COMPRESSION_ALG="lzo" ;;
        esac
    fi

    # Настройка шифрования
    echo ""
    echo "Настроить параметры шифрования вручную?"
    until [[ "$CUSTOMIZE_ENC" =~ (y|n) ]]; do
        read -rp "Настроить шифрование? [y/n]: " -e -i n CUSTOMIZE_ENC
    done
    if [[ "$CUSTOMIZE_ENC" == "n" ]]; then
        CIPHER="AES-128-GCM"
        CERT_TYPE="1"
        CERT_CURVE="prime256v1"
        CC_CIPHER="TLS-ECDHE-ECDSA-WITH-AES-128-GCM-SHA256"
        DH_TYPE="1"
        DH_CURVE="prime256v1"
        HMAC_ALG="SHA256"
        TLS_SIG="1"
    else
        # Выбор шифра
        echo "Выберите шифр для канала данных:"
        echo "   1) AES-128-GCM (рекомендуется)"
        echo "   2) AES-192-GCM"
        echo "   3) AES-256-GCM"
        echo "   4) AES-128-CBC"
        echo "   5) AES-192-CBC"
        echo "   6) AES-256-CBC"
        until [[ "$CIPHER_CHOICE" =~ ^[1-6]$ ]]; do
            read -rp "Шифр [1-6]: " -e -i 1 CIPHER_CHOICE
        done
        case "$CIPHER_CHOICE" in
            1) CIPHER="AES-128-GCM" ;;
            2) CIPHER="AES-192-GCM" ;;
            3) CIPHER="AES-256-GCM" ;;
            4) CIPHER="AES-128-CBC" ;;
            5) CIPHER="AES-192-CBC" ;;
            6) CIPHER="AES-256-CBC" ;;
        esac

        # Выбор типа сертификата
        echo "Выберите тип сертификата:"
        echo "   1) ECDSA (рекомендуется)"
        echo "   2) RSA"
        until [[ "$CERT_TYPE" =~ ^[1-2]$ ]]; do
            read -rp "Тип ключа [1-2]: " -e -i 1 CERT_TYPE
        done
        case "$CERT_TYPE" in
            1)
                echo "Выберите кривую для ECDSA:"
                echo "   1) prime256v1 (рекомендуется)"
                echo "   2) secp384r1"
                echo "   3) secp521r1"
                until [[ "$CERT_CURVE_CHOICE" =~ ^[1-3]$ ]]; do
                    read -rp "Кривая [1-3]: " -e -i 1 CERT_CURVE_CHOICE
                done
                case "$CERT_CURVE_CHOICE" in
                    1) CERT_CURVE="prime256v1" ;;
                    2) CERT_CURVE="secp384r1" ;;
                    3) CERT_CURVE="secp521r1" ;;
                esac
                ;;
            2)
                echo "Выберите размер ключа RSA:"
                echo "   1) 2048 бит (рекомендуется)"
                echo "   2) 3072 бит"
                echo "   3) 4096 бит"
                until [[ "$RSA_KEY_SIZE_CHOICE" =~ ^[1-3]$ ]]; do
                    read -rp "Размер ключа RSA [1-3]: " -e -i 1 RSA_KEY_SIZE_CHOICE
                done
                case "$RSA_KEY_SIZE_CHOICE" in
                    1) RSA_KEY_SIZE="2048" ;;
                    2) RSA_KEY_SIZE="3072" ;;
                    3) RSA_KEY_SIZE="4096" ;;
                esac
                ;;
        esac

        # Выбор шифра управляющего канала
        echo "Выберите шифр управляющего канала:"
        case "$CERT_TYPE" in
            1)
                echo "   1) ECDHE-ECDSA-AES-128-GCM-SHA256 (рекомендуется)"
                echo "   2) ECDHE-ECDSA-AES-256-GCM-SHA384"
                until [[ "$CC_CIPHER_CHOICE" =~ ^[1-2]$ ]]; do
                    read -rp "Шифр [1-2]: " -e -i 1 CC_CIPHER_CHOICE
                done
                case "$CC_CIPHER_CHOICE" in
                    1) CC_CIPHER="TLS-ECDHE-ECDSA-WITH-AES-128-GCM-SHA256" ;;
                    2) CC_CIPHER="TLS-ECDHE-ECDSA-WITH-AES-256-GCM-SHA384" ;;
                esac
                ;;
            2)
                echo "   1) ECDHE-RSA-AES-128-GCM-SHA256 (рекомендуется)"
                echo "   2) ECDHE-RSA-AES-256-GCM-SHA384"
                until [[ "$CC_CIPHER_CHOICE" =~ ^[1-2]$ ]]; do
                    read -rp "Шифр [1-2]: " -e -i 1 CC_CIPHER_CHOICE
                done
                case "$CC_CIPHER_CHOICE" in
                    1) CC_CIPHER="TLS-ECDHE-RSA-WITH-AES-128-GCM-SHA256" ;;
                    2) CC_CIPHER="TLS-ECDHE-RSA-WITH-AES-256-GCM-SHA384" ;;
                esac
                ;;
        esac

        # Выбор типа Diffie-Hellman
        echo "Выберите тип ключа Diffie-Hellman:"
        echo "   1) ECDH (рекомендуется)"
        echo "   2) DH"
        until [[ "$DH_TYPE" =~ ^[1-2]$ ]]; do
            read -rp "Тип DH [1-2]: " -e -i 1 DH_TYPE
        done
        case "$DH_TYPE" in
            1)
                echo "Выберите кривую для ECDH:"
                echo "   1) prime256v1 (рекомендуется)"
                echo "   2) secp384r1"
                echo "   3) secp521r1"
                until [[ "$DH_CURVE_CHOICE" =~ ^[1-3]$ ]]; do
                    read -rp "Кривая [1-3]: " -e -i 1 DH_CURVE_CHOICE
                done
                case "$DH_CURVE_CHOICE" in
                    1) DH_CURVE="prime256v1" ;;
                    2) DH_CURVE="secp384r1" ;;
                    3) DH_CURVE="secp521r1" ;;
                esac
                ;;
            2)
                echo "Выберите размер ключа DH:"
                echo "   1) 2048 бит (рекомендуется)"
                echo "   2) 3072 бит"
                echo "   3) 4096 бит"
                until [[ "$DH_KEY_SIZE_CHOICE" =~ ^[1-3]$ ]]; do
                    read -rp "Размер DH [1-3]: " -e -i 1 DH_KEY_SIZE_CHOICE
                done
                case "$DH_KEY_SIZE_CHOICE" in
                    1) DH_KEY_SIZE="2048" ;;
                    2) DH_KEY_SIZE="3072" ;;
                    3) DH_KEY_SIZE="4096" ;;
                esac
                ;;
        esac

        # Выбор алгоритма HMAC
        echo "Выберите алгоритм HMAC:"
        until [[ "$HMAC_ALG_CHOICE" =~ ^[1-3]$ ]]; do
            read -rp "Алгоритм [1-SHA256, 2-SHA384, 3-SHA512]: " -e -i 1 HMAC_ALG_CHOICE
        done
        case "$HMAC_ALG_CHOICE" in
            1) HMAC_ALG="SHA256" ;;
            2) HMAC_ALG="SHA384" ;;
            3) HMAC_ALG="SHA512" ;;
        esac

        # Выбор механизма безопасности
        echo "Выберите механизм защиты управляющего канала:"
        echo "   1) tls-crypt (рекомендуется)"
        echo "   2) tls-auth"
        until [[ "$TLS_SIG" =~ ^[1-2]$ ]]; do
            read -rp "Механизм [1-2]: " -e -i 1 TLS_SIG
        done
    fi

    echo "Все данные собраны. Готовы к установке OpenVPN."
    APPROVE_INSTALL=${APPROVE_INSTALL:-n}
    [[ "$APPROVE_INSTALL" =~ n ]] && read -n1 -r -p "Нажмите любую клавишу для продолжения..."
}

# Функция проверки и установки локали ru_RU.UTF-8
function installLocaleRU() {
    if locale -a | grep -q "ru_RU.utf8"; then
        echo "Локаль ru_RU.UTF-8 уже доступна."
    else
        echo "Локаль ru_RU.UTF-8 не найдена, запускаем настройку..."
        sudo dpkg-reconfigure locales || { echo "Ошибка настройки локалей"; exit 1; }
        export LANG="ru_RU.UTF-8"
        echo "Локаль ru_RU.UTF-8 установлена для текущей сессии."
    fi
}

# Функция установки OpenVPN
function installOpenVPN() {
    if [[ "$AUTO_INSTALL" == "y" ]]; then
        APPROVE_INSTALL="y"
        APPROVE_IP="y"
        IPV6_SUPPORT=${IPV6_SUPPORT:-n}
        PORT_CHOICE=${PORT_CHOICE:-1}
        PROTOCOL_CHOICE=${PROTOCOL_CHOICE:-1}
        COMPRESSION_ENABLED=${COMPRESSION_ENABLED:-n}
        CUSTOMIZE_ENC=${CUSTOMIZE_ENC:-n}
        CLIENT=${CLIENT:-client}
        PASS=${PASS:-1}
        CONTINUE=${CONTINUE:-y}
        if [[ "$IPV6_SUPPORT" == "y" ]]; then
            PUBLIC_IP=$(curl -f --retry 5 --retry-connrefused https://ip.seeip.org || dig -6 TXT +short o-o.myaddr.l.google.com @ns1.google.com | tr -d '"')
        else
            PUBLIC_IP=$(curl -f --retry 5 --retry-connrefused -4 https://ip.seeip.org || dig -4 TXT +short o-o.myaddr.l.google.com @ns1.google.com | tr -d '"')
        fi
        ENDPOINT=${ENDPOINT:-$PUBLIC_IP}
    fi

    installQuestions

    # Определение сетевого интерфейса
    NIC=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
    if [[ -z "$NIC" && "$IPV6_SUPPORT" == "y" ]]; then
        NIC=$(ip -6 route show default | sed -ne 's/^default .* dev \([^ ]*\) .*$/\1/p')
    fi
    if [[ -z "$NIC" ]]; then
        echo "Не удалось определить сетевой интерфейс."
        until [[ "$CONTINUE" =~ (y|n) ]]; do
            read -rp "Продолжить? [y/n]: " -e CONTINUE
        done
        [[ "$CONTINUE" == "n" ]] && exit 1
    fi

    # Установка OpenVPN
    if [[ ! -e /etc/openvpn/server.conf ]]; then
        case "$OS" in
            "debian"|"ubuntu")
                apt-get update || { echo "Ошибка обновления пакетов"; exit 1; }
                apt-get -y install ca-certificates gnupg openvpn iptables openssl wget curl || { echo "Ошибка установки пакетов"; exit 1; }
                if [[ "$VERSION_ID" == "16.04" ]]; then
                    echo "deb http://build.openvpn.net/debian/openvpn/stable xenial main" >/etc/apt/sources.list.d/openvpn.list
                    wget -O - https://swupdate.openvpn.net/repos/repo-public.gpg | apt-key add -
                    apt-get update
                    apt-get install -y openvpn
                fi
                ;;
            "centos")
                yum install -y epel-release openvpn iptables openssl wget ca-certificates curl tar 'policycoreutils-python*' || { echo "Ошибка установки пакетов"; exit 1; }
                ;;
            "oracle")
                yum install -y oracle-epel-release-el8 || { echo "Ошибка установки EPEL"; exit 1; }
                yum-config-manager --enable ol8_developer_EPEL
                yum install -y openvpn iptables openssl wget ca-certificates curl tar policycoreutils-python-utils || { echo "Ошибка установки пакетов"; exit 1; }
                ;;
            "amzn")
                amazon-linux-extras install -y epel
                yum install -y openvpn iptables openssl wget ca-certificates curl || { echo "Ошибка установки пакетов"; exit 1; }
                ;;
            "fedora")
                dnf install -y openvpn iptables openssl wget ca-certificates curl policycoreutils-python-utils || { echo "Ошибка установки пакетов"; exit 1; }
                ;;
            "arch")
                pacman --needed --noconfirm -Syu openvpn iptables openssl wget ca-certificates curl || { echo "Ошибка установки пакетов"; exit 1; }
                ;;
        esac
        [[ -d /etc/openvpn/easy-rsa/ ]] && rm -rf /etc/openvpn/easy-rsa/
    fi

    # Определение группы без привилегий
    NOGROUP=$(grep -qs "^nogroup:" /etc/group && echo "nogroup" || echo "nobody")

    # Установка easy-rsa
    if [[ ! -d /etc/openvpn/easy-rsa/ ]]; then
        if ! command -v curl >/dev/null 2>&1; then
            echo "Установка curl..."
            case "$OS" in
                "debian"|"ubuntu") apt-get update && apt-get install -y curl ;;
                "centos"|"amzn"|"oracle") yum install -y curl ;;
                "fedora") dnf install -y curl ;;
                "arch") pacman -Syu --noconfirm curl ;;
            esac
            command -v curl >/dev/null 2>&1 || { echo "Ошибка установки curl"; exit 1; }
        fi

        latest_version=$(curl -s https://api.github.com/repos/OpenVPN/easy-rsa/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/' || echo "3.1.2")
        echo "Выберите версию easy-rsa:"
        echo "   1) Последняя версия: $latest_version (рекомендуется)"
        echo "   2) Версия 3.1.2"
        until [[ "$EASYRSA_VERSION_CHOICE" =~ ^[1-2]$ ]]; do
            read -rp "Выбор версии [1-2]: " -e -i 1 EASYRSA_VERSION_CHOICE
        done
        version=$([[ "$EASYRSA_VERSION_CHOICE" == "1" ]] && echo "$latest_version" || echo "3.1.2")
        echo "Установка easy-rsa версии $version..."

        wget -O ~/easy-rsa.tgz "https://github.com/OpenVPN/easy-rsa/releases/download/v${version}/EasyRSA-${version}.tgz" || { echo "Ошибка скачивания easy-rsa"; exit 1; }
        mkdir -p /etc/openvpn/easy-rsa
        tar xzf ~/easy-rsa.tgz --strip-components=1 --no-same-owner --directory /etc/openvpn/easy-rsa || { echo "Ошибка распаковки easy-rsa"; exit 1; }
        rm -f ~/easy-rsa.tgz

        cd /etc/openvpn/easy-rsa/ || { echo "Ошибка перехода в easy-rsa"; exit 1; }
        case "$CERT_TYPE" in
            1) echo -e "set_var EASYRSA_ALGO ec\nset_var EASYRSA_CURVE $CERT_CURVE" > vars ;;
            2) echo "set_var EASYRSA_KEY_SIZE $RSA_KEY_SIZE" > vars ;;
        esac

        SERVER_CN="cn_$(head /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)"
        echo "$SERVER_CN" > SERVER_CN_GENERATED
        SERVER_NAME="server"
        echo "$SERVER_NAME" > SERVER_NAME_GENERATED

        ./easyrsa init-pki || { echo "Ошибка инициализации PKI"; exit 1; }
        EASYRSA_CA_EXPIRE=3650 ./easyrsa --batch --req-cn="$SERVER_CN" build-ca nopass || { echo "Ошибка создания CA"; exit 1; }
        if [[ "$DH_TYPE" == "2" ]]; then
            openssl dhparam -out dh.pem "$DH_KEY_SIZE" || { echo "Ошибка генерации DH"; exit 1; }
        fi
        EASYRSA_CERT_EXPIRE=3650 ./easyrsa --batch build-server-full "$SERVER_NAME" nopass || { echo "Ошибка создания сертификата сервера"; exit 1; }
        EASYRSA_CRL_DAYS=3650 ./easyrsa gen-crl || { echo "Ошибка генерации CRL"; exit 1; }
        case "$TLS_SIG" in
            1) openvpn --genkey --secret /etc/openvpn/tls-crypt.key || { echo "Ошибка генерации tls-crypt"; exit 1; } ;;
            2) openvpn --genkey --secret /etc/openvpn/tls-auth.key || { echo "Ошибка генерации tls-auth"; exit 1; } ;;
        esac
    else
        cd /etc/openvpn/easy-rsa/ || { echo "Ошибка перехода в easy-rsa"; exit 1; }
        SERVER_NAME=$(cat SERVER_NAME_GENERATED)
    fi

    # Копирование файлов
    cp pki/ca.crt pki/private/ca.key "pki/issued/$SERVER_NAME.crt" "pki/private/$SERVER_NAME.key" pki/crl.pem /etc/openvpn || { echo "Ошибка копирования файлов"; exit 1; }
    [[ "$DH_TYPE" == "2" ]] && cp dh.pem /etc/openvpn
    chmod 644 /etc/openvpn/crl.pem

    # Создание конфигурации сервера
    {
        echo "port $PORT"
        [[ "$IPV6_SUPPORT" == "n" ]] && echo "proto $PROTOCOL" || echo "proto ${PROTOCOL}6"
        echo "dev tun
user nobody
group $NOGROUP
persist-key
persist-tun
keepalive 10 120
topology subnet
server ${IPVPN}.0 255.255.255.0
ifconfig-pool-persist ipp.txt"
        [[ "$IPV6_SUPPORT" == "y" ]] && echo "server-ipv6 fd42:42:42:42::/112
tun-ipv6
push tun-ipv6
push \"route-ipv6 2000::/3\"
push \"redirect-gateway ipv6\""
        [[ "$COMPRESSION_ENABLED" == "y" ]] && echo "compress $COMPRESSION_ALG"
        if [[ "$DH_TYPE" == "1" ]]; then
            echo "dh none
ecdh-curve $DH_CURVE"
        else
            echo "dh dh.pem"
        fi
        case "$TLS_SIG" in
            1) echo "tls-crypt tls-crypt.key" ;;
            2) echo "tls-auth tls-auth.key 0" ;;
        esac
        echo "crl-verify crl.pem
ca ca.crt
cert $SERVER_NAME.crt
key $SERVER_NAME.key
auth $HMAC_ALG
cipher $CIPHER
ncp-ciphers $CIPHER
tls-server
tls-version-min 1.2
tls-cipher $CC_CIPHER
client-config-dir /etc/openvpn/ccd
status /var/log/openvpn/status.log
verb 3"
    } > /etc/openvpn/server.conf || { echo "Ошибка создания server.conf"; exit 1; }

    mkdir -p /etc/openvpn/ccd /var/log/openvpn
    touch /etc/openvpn/ccd/_default

    # Включение маршрутизации
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-openvpn.conf
    [[ "$IPV6_SUPPORT" == "y" ]] && echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.d/99-openvpn.conf
    sysctl --system || { echo "Ошибка применения sysctl"; exit 1; }

    # Настройка SELinux
    if command -v sestatus >/dev/null 2>&1 && sestatus | grep -qs "enforcing" && [[ "$PORT" != "1194" ]]; then
        semanage port -a -t openvpn_port_t -p "$PROTOCOL" "$PORT" || { echo "Ошибка настройки SELinux"; exit 1; }
    fi

    # Запуск OpenVPN
    case "$OS" in
        "arch"|"fedora"|"centos"|"oracle")
            cp /usr/lib/systemd/system/openvpn-server@.service /etc/systemd/system/ || { echo "Ошибка копирования службы"; exit 1; }
            sed -i 's|LimitNPROC|#LimitNPROC|' /etc/systemd/system/openvpn-server@.service
            sed -i 's|/etc/openvpn/server|/etc/openvpn|' /etc/systemd/system/openvpn-server@.service
            systemctl daemon-reload
            systemctl enable openvpn-server@server
            systemctl restart openvpn-server@server || { echo "Ошибка запуска OpenVPN"; exit 1; }
            ;;
        "ubuntu")
            if [[ "$VERSION_ID" == "16.04" ]]; then
                systemctl enable openvpn
                systemctl start openvpn || { echo "Ошибка запуска OpenVPN"; exit 1; }
            else
                cp /lib/systemd/system/openvpn\@.service /etc/systemd/system/ || { echo "Ошибка копирования службы"; exit 1; }
                sed -i 's|LimitNPROC|#LimitNPROC|' /etc/systemd/system/openvpn\@.service
                sed -i 's|/etc/openvpn/server|/etc/openvpn|' /etc/systemd/system/openvpn\@.service
                systemctl daemon-reload
                systemctl enable openvpn@server
                systemctl restart openvpn@server || { echo "Ошибка запуска OpenVPN"; exit 1; }
            fi
            ;;
    esac

    # Настройка iptables
    mkdir -p /etc/iptables
    {
        echo "#!/bin/sh"
        echo "iptables -t nat -I POSTROUTING 1 -s ${IPVPN}.0/24 -o $NIC -j MASQUERADE"
        echo "iptables -I INPUT 1 -i tun0 -j ACCEPT"
        echo "iptables -I FORWARD 1 -i $NIC -o tun0 -j ACCEPT"
        echo "iptables -I FORWARD 1 -i tun0 -o $NIC -j ACCEPT"
        echo "iptables -I INPUT 1 -i $NIC -p $PROTOCOL --dport $PORT -j ACCEPT"
        [[ "$IPV6_SUPPORT" == "y" ]] && echo "ip6tables -t nat -I POSTROUTING 1 -s fd42:42:42:42::/112 -o $NIC -j MASQUERADE
ip6tables -I INPUT 1 -i tun0 -j ACCEPT
ip6tables -I FORWARD 1 -i $NIC -o tun0 -j ACCEPT
ip6tables -I FORWARD 1 -i tun0 -o $NIC -j ACCEPT
ip6tables -I INPUT 1 -i $NIC -p $PROTOCOL --dport $PORT -j ACCEPT"
    } > /etc/iptables/add-openvpn-rules.sh || { echo "Ошибка создания правил iptables"; exit 1; }

    {
        echo "#!/bin/sh"
        echo "iptables -t nat -D POSTROUTING -s ${IPVPN}.0/24 -o $NIC -j MASQUERADE"
        echo "iptables -D INPUT -i tun0 -j ACCEPT"
        echo "iptables -D FORWARD -i $NIC -o tun0 -j ACCEPT"
        echo "iptables -D FORWARD -i tun0 -o $NIC -j ACCEPT"
        echo "iptables -D INPUT -i $NIC -p $PROTOCOL --dport $PORT -j ACCEPT"
        [[ "$IPV6_SUPPORT" == "y" ]] && echo "ip6tables -t nat -D POSTROUTING -s fd42:42:42:42::/112 -o $NIC -j MASQUERADE
ip6tables -D INPUT -i tun0 -j ACCEPT
ip6tables -D FORWARD -i $NIC -o tun0 -j ACCEPT
ip6tables -D FORWARD -i tun0 -o $NIC -j ACCEPT
ip6tables -D INPUT -i $NIC -p $PROTOCOL --dport $PORT -j ACCEPT"
    } > /etc/iptables/rm-openvpn-rules.sh || { echo "Ошибка создания правил удаления iptables"; exit 1; }

    chmod +x /etc/iptables/add-openvpn-rules.sh /etc/iptables/rm-openvpn-rules.sh

    # Настройка службы iptables
    cat << EOF > /etc/systemd/system/iptables-openvpn.service || { echo "Ошибка создания службы iptables"; exit 1; }
[Unit]
Description=iptables rules for OpenVPN
Before=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/etc/iptables/add-openvpn-rules.sh
ExecStop=/etc/iptables/rm-openvpn-rules.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable iptables-openvpn
    systemctl start iptables-openvpn || { echo "Ошибка запуска службы iptables"; exit 1; }

    [[ -n "$ENDPOINT" ]] && IP="$ENDPOINT"

    # Создание шаблона клиента
    {
        echo "client"
        [[ "$PROTOCOL" == "udp" ]] && echo "proto udp\nexplicit-exit-notify" || echo "proto tcp-client"
        echo "remote $IP $PORT
dev tun
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
verify-x509-name $SERVER_NAME name
auth $HMAC_ALG
auth-nocache
cipher $CIPHER
tls-client
tls-version-min 1.2
tls-cipher $CC_CIPHER
verb 3"
        [[ "$COMPRESSION_ENABLED" == "y" ]] && echo "compress $COMPRESSION_ALG"
    } > /etc/openvpn/client-template.txt || { echo "Ошибка создания шаблона клиента"; exit 1; }

    newClient
    echo "Для добавления новых клиентов запустите скрипт снова!"
}

# Функция создания нового клиента
function newClient() {
    echo "Укажите имя клиента (только буквы, цифры, _ или -):"
    until [[ "$CLIENT" =~ ^[a-zA-Z0-9_-]+$ ]]; do
        read -rp "Имя клиента: " -e CLIENT
    done

    CLIENTEXISTS=$(tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt | grep -c -E "/CN=$CLIENT\$")
    if [[ "$CLIENTEXISTS" == "1" ]]; then
        echo "Ошибка: Клиент $CLIENT уже существует."
        exit 1
    fi

    cd /etc/openvpn/easy-rsa/ || { echo "Ошибка перехода в easy-rsa"; exit 1; }
    EASYRSA_CERT_EXPIRE=3650 ./easyrsa --batch build-client-full "$CLIENT" nopass || { echo "Ошибка создания клиента"; exit 1; }
    echo "Клиент $CLIENT добавлен."

    homeDir="/etc/openvpn/_OpenVPN_KEY"
    mkdir -p "$homeDir" || { echo "Ошибка создания директории $homeDir"; exit 1; }

    TLS_SIG=$(grep -qs "^tls-crypt" /etc/openvpn/server.conf && echo "1" || (grep -qs "^tls-auth" /etc/openvpn/server.conf && echo "2"))

    cp /etc/openvpn/client-template.txt "$homeDir/$CLIENT.ovpn" || { echo "Ошибка копирования шаблона"; exit 1; }
    {
        echo "<ca>"; cat "/etc/openvpn/easy-rsa/pki/ca.crt"; echo "</ca>"
        echo "<cert>"; awk '/BEGIN/,/END CERTIFICATE/' "/etc/openvpn/easy-rsa/pki/issued/$CLIENT.crt"; echo "</cert>"
        echo "<key>"; cat "/etc/openvpn/easy-rsa/pki/private/$CLIENT.key"; echo "</key>"
        case "$TLS_SIG" in
            1) echo "<tls-crypt>"; cat /etc/openvpn/tls-crypt.key; echo "</tls-crypt>" ;;
            2) echo "key-direction 1\n<tls-auth>"; cat /etc/openvpn/tls-auth.key; echo "</tls-auth>" ;;
        esac
    } >> "$homeDir/$CLIENT.ovpn" || { echo "Ошибка создания .ovpn файла"; exit 1; }

    echo "Файл конфигурации сохранен в $homeDir/$CLIENT.ovpn."
    echo "Скопируйте _default CCD для $CLIENT..."
    cp /etc/openvpn/ccd/_default /etc/openvpn/ccd/$CLIENT || { echo "Ошибка копирования CCD"; exit 1; }
    cat /etc/openvpn/ccd/$CLIENT
    echo "------------------------------------------------------------------------------"
    exit 0
}

# Функция отзыва клиента
function revokeClient() {
    NUMBEROFCLIENTS=$(tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt | grep -c "^V")
    if [[ "$NUMBEROFCLIENTS" == "0" ]]; then
        echo "Нет активных клиентов!"
        exit 1
    fi

    echo "Выберите клиента для отзыва:"
    tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt | grep "^V" | cut -d '=' -f 2 | nl -s ') '
    until [[ "$CLIENTNUMBER" -ge 1 && "$CLIENTNUMBER" -le "$NUMBEROFCLIENTS" ]]; do
        read -rp "Выберите клиента [1-$NUMBEROFCLIENTS]: " CLIENTNUMBER
    done
    CLIENT=$(tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt | grep "^V" | cut -d '=' -f 2 | sed -n "${CLIENTNUMBER}p")

    cd /etc/openvpn/easy-rsa/ || { echo "Ошибка перехода в easy-rsa"; exit 1; }
    ./easyrsa --batch revoke "$CLIENT" || { echo "Ошибка отзыва клиента"; exit 1; }
    EASYRSA_CRL_DAYS=3650 ./easyrsa gen-crl || { echo "Ошибка генерации CRL"; exit 1; }
    rm -f /etc/openvpn/crl.pem
    cp /etc/openvpn/easy-rsa/pki/crl.pem /etc/openvpn/crl.pem || { echo "Ошибка копирования CRL"; exit 1; }
    chmod 644 /etc/openvpn/crl.pem
    rm -f "/etc/openvpn/_OpenVPN_KEY/$CLIENT.ovpn" 2>/dev/null
    sed -i "/^$CLIENT,.*/d" /etc/openvpn/ipp.txt || { echo "Ошибка обновления ipp.txt"; exit 1; }
    cp /etc/openvpn/easy-rsa/pki/index.txt{,.bk} || { echo "Ошибка создания бэкапа index.txt"; exit 1; }
    rm -f /etc/openvpn/ccd/$CLIENT 2>/dev/null
    echo "Сертификат клиента $CLIENT отозван."
}

# Функция удаления OpenVPN
function removeOpenVPN() {
    echo ""
    read -rp "Вы действительно хотите удалить OpenVPN? [y/n]: " -e -i n REMOVE
    if [[ "$REMOVE" == "y" ]]; then
        PORT=$(grep '^port ' /etc/openvpn/server.conf | cut -d " " -f 2)
        PROTOCOL=$(grep '^proto ' /etc/openvpn/server.conf | cut -d " " -f 2)

        case "$OS" in
            "fedora"|"arch"|"centos"|"oracle")
                systemctl disable openvpn-server@server
                systemctl stop openvpn-server@server
                rm -f /etc/systemd/system/openvpn-server@.service
                ;;
            "ubuntu")
                if [[ "$VERSION_ID" == "16.04" ]]; then
                    systemctl disable openvpn
                    systemctl stop openvpn
                else
                    systemctl disable openvpn@server
                    systemctl stop openvpn@server
                    rm -f /etc/systemd/system/openvpn\@.service
                fi
                ;;
        esac

        systemctl stop iptables-openvpn
        systemctl disable iptables-openvpn
        rm -f /etc/systemd/system/iptables-openvpn.service
        systemctl daemon-reload
        rm -f /etc/iptables/add-openvpn-rules.sh /etc/iptables/rm-openvpn-rules.sh

        if command -v sestatus >/dev/null 2>&1 && sestatus | grep -qs "enforcing" && [[ "$PORT" != "1194" ]]; then
            semanage port -d -t openvpn_port_t -p "$PROTOCOL" "$PORT"
        fi

        case "$OS" in
            "debian"|"ubuntu") apt-get remove --purge -y openvpn; rm -f /etc/apt/sources.list.d/openvpn.list; apt-get update ;;
            "arch") pacman --noconfirm -R openvpn ;;
            "centos"|"amzn"|"oracle") yum remove -y openvpn ;;
            "fedora") dnf remove -y openvpn ;;
        esac

        find /home/ -maxdepth 2 -name "*.ovpn" -delete
        find /root/ -maxdepth 1 -name "*.ovpn" -delete
        rm -rf /etc/openvpn /usr/share/doc/openvpn* /etc/sysctl.d/99-openvpn.conf /var/log/openvpn
        rm -f /usr/local/bin/vpn-stat /usr/local/bin/vpn-user

        echo "OpenVPN удален!"
    else
        echo "Удаление отменено!"
    fi
}

# Функция управления меню
function manageMenu() {
    echo "Добро пожаловать в OpenVPN-install!"
    echo "Репозиторий: https://github.com/angristan/openvpn-install"
    echo "OpenVPN уже установлен."
    echo "Выберите действие:"
    echo "   1) Добавить нового пользователя"
    echo "   2) Отозвать пользователя"
    echo "   3) Удалить OpenVPN"
    echo "   4) Выход"
    until [[ "$MENU_OPTION" =~ ^[1-4]$ ]]; do
        read -rp "Выберите опцию [1-4]: " MENU_OPTION
    done
    case "$MENU_OPTION" in
        1) newClient ;;
        2) revokeClient ;;
        3) removeOpenVPN ;;
        4) exit 0 ;;
    esac
}

# Основной запуск
initialCheck
if [[ -e /etc/openvpn/server.conf && "$AUTO_INSTALL" != "y" ]]; then
    manageMenu
else
    installLocaleRU
    installOpenVPN
fi
