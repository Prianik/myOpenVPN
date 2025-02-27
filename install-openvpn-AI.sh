#!/bin/bash
# shellcheck disable=SC1091,SC2164,SC2034,SC1072,SC1073,SC1009

# Secure OpenVPN server installer for Debian, Ubuntu, CentOS, Amazon Linux 2, Fedora, Oracle Linux 8, Arch Linux, Rocky Linux, and AlmaLinux.
# Project repository: https://github.com/angristan/openvpn-install

# Define base IP for the VPN network
IPVPN=10.91.0

# Function to check if the script is running as root
function isRoot() {
    if [ "$EUID" -ne 0 ]; then
        return 1  # Returns 1 if not root
    fi
}

# Function to check if TUN device is available
function tunAvailable() {
    if [ ! -e /dev/net/tun ]; then
        return 1  # Returns 1 if TUN is not available
    fi
}

# Function to determine the operating system
function checkOS() {
    if [[ -e /etc/debian_version ]]; then
        OS="debian"  # Identify as Debian-based
        source /etc/os-release

        # Check specific distributions and versions
        if [[ $ID == "debian" || $ID == "raspbian" ]]; then
            if [[ $VERSION_ID -lt 9 ]]; then
                echo "⚠️ Your version of Debian is not supported."
                echo "However, if you're using Debian >= 9 or unstable/testing, you can continue at your own risk."
                until [[ $CONTINUE =~ (y|n) ]]; do
                    read -rp "Continue? [y/n]: " -e CONTINUE
                done
                if [[ $CONTINUE == "n" ]]; then
                    exit 1
                fi
            fi
        elif [[ $ID == "ubuntu" ]]; then
            OS="ubuntu"
            MAJOR_UBUNTU_VERSION=$(echo "$VERSION_ID" | cut -d '.' -f1)
            if [[ $MAJOR_UBUNTU_VERSION -lt 16 ]]; then
                echo "⚠️ Your version of Ubuntu is not supported."
                echo "However, if you're using Ubuntu >= 16.04 or beta, you can continue at your own risk."
                until [[ $CONTINUE =~ (y|n) ]]; do
                    read -rp "Continue? [y/n]: " -e CONTINUE
                done
                if [[ $CONTINUE == "n" ]]; then
                    exit 1
                fi
            fi
        fi
    elif [[ -e /etc/system-release ]]; then
        source /etc/os-release
        if [[ $ID == "fedora" || $ID_LIKE == "fedora" ]]; then
            OS="fedora"
        fi
        if [[ $ID == "centos" || $ID == "rocky" || $ID == "almalinux" ]]; then
            OS="centos"
            if [[ ${VERSION_ID%.*} -lt 7 ]]; then
                echo "⚠️ Your version of CentOS is not supported."
                echo "The script only supports CentOS 7 and CentOS 8."
                exit 1
            fi
        fi
        if [[ $ID == "ol" ]]; then
            OS="oracle"
            if [[ ! $VERSION_ID =~ (8) ]]; then
                echo "Your version of Oracle Linux is not supported."
                echo "The script only supports Oracle Linux 8."
                exit 1
            fi
        fi
        if [[ $ID == "amzn" ]]; then
            OS="amzn"
            if [[ $VERSION_ID != "2" ]]; then
                echo "⚠️ Your version of Amazon Linux is not supported."
                echo "The script only supports Amazon Linux 2."
                exit 1
            fi
        fi
    elif [[ -e /etc/arch-release ]]; then
        OS=arch
    else
        echo "It seems this installer is not running on a supported system (Debian, Ubuntu, Fedora, CentOS, Amazon Linux 2, Oracle Linux 8, or Arch Linux)"
        exit 1
    fi
}

# Function for initial checks
function initialCheck() {
    if ! isRoot; then
        echo "Sorry, this script must be run as root"
        exit 1
    fi
    if ! tunAvailable; then
        echo "TUN is not available"
        exit 1
    fi
    checkOS
}

# Function to ask setup questions
function installQuestions() {
    echo "Welcome to the OpenVPN installer!"
    echo "The Git repository is available at: https://github.com/angristan/openvpn-install"
    echo ""

    echo "I need to ask you a few questions before starting the setup."
    echo "You can leave the default options by pressing Enter if they suit you."
    echo ""
    echo "I need to know the IPv4 address of the network interface OpenVPN will listen on."
    echo "If the server is not behind NAT, this should be your public IPv4 address."

    # Automatically detect public IPv4
    IP=$(ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | head -1)

    if [[ -z $IP ]]; then
        # If IPv4 is not found, try IPv6
        IP=$(ip -6 addr | sed -ne 's|^.* inet6 \([^/]*\)/.* scope global.*$|\1|p' | head -1)
    fi
    APPROVE_IP=${APPROVE_IP:-n}
    if [[ $APPROVE_IP =~ n ]]; then
        read -rp "IP address: " -e -i "$IP" IP
    fi

    # Check if the server is behind NAT
    if echo "$IP" | grep -qE '^(10\.|172\.1[6789]\.|172\.2[0-9]\.|172\.3[01]\.|192\.168)'; then
        echo ""
        echo "It seems this server is behind NAT. What is its public IPv4 address or hostname?"
        echo "This is needed for clients to connect to the server."

        PUBLICIP=$(curl -s https://api.ipify.org)
        until [[ $ENDPOINT != "" ]]; do
            read -rp "Public IPv4 address or hostname: " -e -i "$PUBLICIP" ENDPOINT
        done
    fi

    echo ""
    echo "Checking for IPv6 connectivity..."
    echo ""
    if type ping6 >/dev/null 2>&1; then
        PING6="ping6 -c3 ipv6.google.com > /dev/null 2>&1"
    else
        PING6="ping -6 -c3 ipv6.google.com > /dev/null 2>&1"
    fi
    if eval "$PING6"; then
        echo "Your host supports IPv6."
        SUGGESTION="y"
    else
        echo "Your host does not support IPv6."
        SUGGESTION="n"
    fi
    echo ""
    until [[ $IPV6_SUPPORT =~ (y|n) ]]; do
        read -rp "Enable IPv6 support (NAT)? [y/n]: " -e -i $SUGGESTION IPV6_SUPPORT
    done

    # Port selection for OpenVPN
    echo ""
    echo "Which port do you want OpenVPN to listen on?"
    echo "   1) Default: 1194"
    echo "   2) Custom"
    echo "   3) Random [49152-65535]"
    until [[ $PORT_CHOICE =~ ^[1-3]$ ]]; do
        read -rp "Port choice [1-3]: " -e -i 1 PORT_CHOICE
    done
    case $PORT_CHOICE in
        1)
            PORT="1194"
            ;;
        2)
            until [[ $PORT =~ ^[0-9]+$ ]] && [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ]; do
                read -rp "Custom port [1-65535]: " -e -i 1194 PORT
            done
            ;;
        3)
            PORT=$(shuf -i49152-65535 -n1)
            echo "Random port: $PORT"
            ;;
    esac

    # Protocol selection
    echo ""
    echo "Which protocol do you want OpenVPN to use?"
    echo "UDP is faster. Use TCP only if UDP is unavailable."
    echo "   1) UDP"
    echo "   2) TCP"
    until [[ $PROTOCOL_CHOICE =~ ^[1-2]$ ]]; do
        read -rp "Protocol [1-2]: " -e -i 2 PROTOCOL_CHOICE
    done
    case $PROTOCOL_CHOICE in
        1)
            PROTOCOL="udp"
            ;;
        2)
            PROTOCOL="tcp"
            ;;
    esac

    # Compression settings
    echo ""
    echo "Do you want to enable compression? It is not recommended due to the VORACLE attack."
    until [[ $COMPRESSION_ENABLED =~ (y|n) ]]; do
        read -rp "Enable compression? [y/n]: " -e -i n COMPRESSION_ENABLED
    done
    if [[ $COMPRESSION_ENABLED == "y" ]]; then
        echo "Choose a compression algorithm (ordered by efficiency):"
        echo "   1) LZ4-v2"
        echo "   2) LZ4"
        echo "   3) LZ0"
        until [[ $COMPRESSION_CHOICE =~ ^[1-3]$ ]]; do
            read -rp "Compression algorithm [1-3]: " -e -i 1 COMPRESSION_CHOICE
        done
        case $COMPRESSION_CHOICE in
            1) COMPRESSION_ALG="lz4-v2" ;;
            2) COMPRESSION_ALG="lz4" ;;
            3) COMPRESSION_ALG="lzo" ;;
        esac
    fi

    # Encryption customization
    echo ""
    echo "Do you want to customize encryption settings?"
    echo "Unless you know what you're doing, stick with the script's default parameters."
    echo "Details: https://github.com/angristan/openvpn-install#security-and-encryption"
    until [[ $CUSTOMIZE_ENC =~ (y|n) ]]; do
        read -rp "Customize encryption settings? [y/n]: " -e -i n CUSTOMIZE_ENC
    done
    if [[ $CUSTOMIZE_ENC == "n" ]]; then
        CIPHER="AES-128-GCM"
        CERT_TYPE="1"  # ECDSA
        CERT_CURVE="prime256v1"
        CC_CIPHER="TLS-ECDHE-ECDSA-WITH-AES-128-GCM-SHA256"
        DH_TYPE="1"  # ECDH
        DH_CURVE="prime256v1"
        HMAC_ALG="SHA256"
        TLS_SIG="1"  # tls-crypt
    else
        echo ""
        echo "Choose a cipher for the data channel:"
        echo "   1) AES-128-GCM (recommended)"
        echo "   2) AES-192-GCM"
        echo "   3) AES-256-GCM"
        echo "   4) AES-128-CBC"
        echo "   5) AES-192-CBC"
        echo "   6) AES-256-CBC"
        until [[ $CIPHER_CHOICE =~ ^[1-6]$ ]]; do
            read -rp "Cipher [1-6]: " -e -i 1 CIPHER_CHOICE
        done
        case $CIPHER_CHOICE in
            1) CIPHER="AES-128-GCM" ;;
            2) CIPHER="AES-192-GCM" ;;
            3) CIPHER="AES-256-GCM" ;;
            4) CIPHER="AES-128-CBC" ;;
            5) CIPHER="AES-192-CBC" ;;
            6) CIPHER="AES-256-CBC" ;;
        esac

        # Certificate type selection
        echo ""
        echo "Choose a certificate type:"
        echo "   1) ECDSA (recommended)"
        echo "   2) RSA"
        until [[ $CERT_TYPE =~ ^[1-2]$ ]]; do
            read -rp "Certificate key type [1-2]: " -e -i 1 CERT_TYPE
        done
        case $CERT_TYPE in
            1)
                echo ""
                echo "Choose a curve for the certificate key:"
                echo "   1) prime256v1 (recommended)"
                echo "   2) secp384r1"
                echo "   3) secp521r1"
                until [[ $CERT_CURVE_CHOICE =~ ^[1-3]$ ]]; do
                    read -rp "Curve [1-3]: " -e -i 1 CERT_CURVE_CHOICE
                done
                case $CERT_CURVE_CHOICE in
                    1) CERT_CURVE="prime256v1" ;;
                    2) CERT_CURVE="secp384r1" ;;
                    3) CERT_CURVE="secp521r1" ;;
                esac
                ;;
            2)
                echo ""
                echo "Choose an RSA key size for the certificate:"
                echo "   1) 2048 bits (recommended)"
                echo "   2) 3072 bits"
                echo "   3) 4096 bits"
                until [[ $RSA_KEY_SIZE_CHOICE =~ ^[1-3]$ ]]; do
                    read -rp "RSA key size [1-3]: " -e -i 1 RSA_KEY_SIZE_CHOICE
                done
                case $RSA_KEY_SIZE_CHOICE in
                    1) RSA_KEY_SIZE="2048" ;;
                    2) RSA_KEY_SIZE="3072" ;;
                    3) RSA_KEY_SIZE="4096" ;;
                esac
                ;;
        esac

        # Control channel cipher selection
        echo ""
        echo "Choose a cipher for the control channel:"
        case $CERT_TYPE in
            1)
                echo "   1) ECDHE-ECDSA-AES-128-GCM-SHA256 (recommended)"
                echo "   2) ECDHE-ECDSA-AES-256-GCM-SHA384"
                until [[ $CC_CIPHER_CHOICE =~ ^[1-2]$ ]]; do
                    read -rp "Control channel cipher [1-2]: " -e -i 1 CC_CIPHER_CHOICE
                done
                case $CC_CIPHER_CHOICE in
                    1) CC_CIPHER="TLS-ECDHE-ECDSA-WITH-AES-128-GCM-SHA256" ;;
                    2) CC_CIPHER="TLS-ECDHE-ECDSA-WITH-AES-256-GCM-SHA384" ;;
                esac
                ;;
            2)
                echo "   1) ECDHE-RSA-AES-128-GCM-SHA256 (recommended)"
                echo "   2) ECDHE-RSA-AES-256-GCM-SHA384"
                until [[ $CC_CIPHER_CHOICE =~ ^[1-2]$ ]]; do
                    read -rp "Control channel cipher [1-2]: " -e -i 1 CC_CIPHER_CHOICE
                done
                case $CC_CIPHER_CHOICE in
                    1) CC_CIPHER="TLS-ECDHE-RSA-WITH-AES-128-GCM-SHA256" ;;
                    2) CC_CIPHER="TLS-ECDHE-RSA-WITH-AES-256-GCM-SHA384" ;;
                esac
                ;;
        esac

        # Diffie-Hellman key type selection
        echo ""
        echo "Choose a Diffie-Hellman key type:"
        echo "   1) ECDH (recommended)"
        echo "   2) DH"
        until [[ $DH_TYPE =~ [1-2] ]]; do
            read -rp "DH key type [1-2]: " -e -i 1 DH_TYPE
        done
        case $DH_TYPE in
            1)
                echo ""
                echo "Choose a curve for the ECDH key:"
                echo "   1) prime256v1 (recommended)"
                echo "   2) secp384r1"
                echo "   3) secp521r1"
                while [[ $DH_CURVE_CHOICE != "1" && $DH_CURVE_CHOICE != "2" && $DH_CURVE_CHOICE != "3" ]]; do
                    read -rp "Curve [1-3]: " -e -i 1 DH_CURVE_CHOICE
                done
                case $DH_CURVE_CHOICE in
                    1) DH_CURVE="prime256v1" ;;
                    2) DH_CURVE="secp384r1" ;;
                    3) DH_CURVE="secp521r1" ;;
                esac
                ;;
            2)
                echo ""
                echo "Choose a Diffie-Hellman key size:"
                echo "   1) 2048 bits (recommended)"
                echo "   2) 3072 bits"
                echo "   3) 4096 bits"
                until [[ $DH_KEY_SIZE_CHOICE =~ ^[1-3]$ ]]; do
                    read -rp "DH key size [1-3]: " -e -i 1 DH_KEY_SIZE_CHOICE
                done
                case $DH_KEY_SIZE_CHOICE in
                    1) DH_KEY_SIZE="2048" ;;
                    2) DH_KEY_SIZE="3072" ;;
                    3) DH_KEY_SIZE="4096" ;;
                esac
                ;;
        esac

        # HMAC digest algorithm selection
        echo ""
        if [[ $CIPHER =~ CBC$ ]]; then
            echo "The digest algorithm authenticates data channel packets and tls-auth packets from the control channel."
        elif [[ $CIPHER =~ GCM$ ]]; then
            echo "The digest algorithm authenticates tls-auth packets from the control channel."
        fi
        echo "Which digest algorithm do you want to use for HMAC?"
        echo "   1) SHA-256 (recommended)"
        echo "   2) SHA-384"
        echo "   3) SHA-512"
        until [[ $HMAC_ALG_CHOICE =~ ^[1-3]$ ]]; do
            read -rp "Digest algorithm [1-3]: " -e -i 1 HMAC_ALG_CHOICE
        done
        case $HMAC_ALG_CHOICE in
            1) HMAC_ALG="SHA256" ;;
            2) HMAC_ALG="SHA384" ;;
            3) HMAC_ALG="SHA512" ;;
        esac

        # Additional control channel security
        echo ""
        echo "You can add an extra layer of security to the control channel with tls-auth or tls-crypt."
        echo "tls-auth authenticates packets, while tls-crypt encrypts and authenticates them."
        echo "   1) tls-crypt (recommended)"
        echo "   2) tls-auth"
        until [[ $TLS_SIG =~ [1-2] ]]; do
            read -rp "Additional control channel security mechanism [1-2]: " -e -i 1 TLS_SIG
        done
    fi

    echo ""
    echo "Okay, that's all I needed. We are ready to set up your OpenVPN server now."
    echo "You will be able to generate a client at the end of the installation."
    APPROVE_INSTALL=${APPROVE_INSTALL:-n}
    if [[ $APPROVE_INSTALL =~ n ]]; then
        read -n1 -r -p "Press any key to continue..."
    fi
}

# Function to install OpenVPN
function installOpenVPN() {
    if [[ $AUTO_INSTALL == "y" ]]; then
        # Set default values for automatic installation
        APPROVE_INSTALL=${APPROVE_INSTALL:-y}
        APPROVE_IP=${APPROVE_IP:-y}
        IPV6_SUPPORT=${IPV6_SUPPORT:-n}
        PORT_CHOICE=${PORT_CHOICE:-1}
        PROTOCOL_CHOICE=${PROTOCOL_CHOICE:-1}
        COMPRESSION_ENABLED=${COMPRESSION_ENABLED:-n}
        CUSTOMIZE_ENC=${CUSTOMIZE_ENC:-n}
        CLIENT=${CLIENT:-client}
        PASS=${PASS:-1}
        CONTINUE=${CONTINUE:-y}

        # Determine public IP for NAT
        if [[ $IPV6_SUPPORT == "y" ]]; then
            if ! PUBLIC_IP=$(curl -f --retry 5 --retry-connrefused https://ip.seeip.org); then
                PUBLIC_IP=$(dig -6 TXT +short o-o.myaddr.l.google.com @ns1.google.com | tr -d '"')
            fi
        else
            if ! PUBLIC_IP=$(curl -f --retry 5 --retry-connrefused -4 https://ip.seeip.org); then
                PUBLIC_IP=$(dig -4 TXT +short o-o.myaddr.l.google.com @ns1.google.com | tr -d '"')
            fi
        fi
        ENDPOINT=${ENDPOINT:-$PUBLIC_IP}
    fi

    # Run setup questions
    installQuestions

    # Determine public interface
    NIC=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
    if [[ -z $NIC ]] && [[ $IPV6_SUPPORT == 'y' ]]; then
        NIC=$(ip -6 route show default | sed -ne 's/^default .* dev \([^ ]*\) .*$/\1/p')
    fi

    if [[ -z $NIC ]]; then
        echo ""
        echo "Could not detect public interface."
        echo "This is needed to configure MASQUERADE."
        until [[ $CONTINUE =~ (y|n) ]]; do
            read -rp "Continue? [y/n]: " -e CONTINUE
        done
        if [[ $CONTINUE == "n" ]]; then
            exit 1
        fi
    fi

    # Install OpenVPN if not already installed
    if [[ ! -e /etc/openvpn/server.conf ]]; then
        if [[ $OS =~ (debian|ubuntu) ]]; then
            apt-get update
            apt-get -y install ca-certificates gnupg
            if [[ $VERSION_ID == "16.04" ]]; then
                echo "deb http://build.openvpn.net/debian/openvpn/stable xenial main" >/etc/apt/sources.list.d/openvpn.list
                wget -O - https://swupdate.openvpn.net/repos/repo-public.gpg | apt-key add -
                apt-get update
            fi
            apt-get install -y openvpn iptables openssl wget ca-certificates curl
        elif [[ $OS == 'centos' ]]; then
            yum install -y epel-release
            yum install -y openvpn iptables openssl wget ca-certificates curl tar 'policycoreutils-python*'
        elif [[ $OS == 'oracle' ]]; then
            yum install -y oracle-epel-release-el8
            yum-config-manager --enable ol8_developer_EPEL
            yum install -y openvpn iptables openssl wget ca-certificates curl tar policycoreutils-python-utils
        elif [[ $OS == 'amzn' ]]; then
            amazon-linux-extras install -y epel
            yum install -y openvpn iptables openssl wget ca-certificates curl
        elif [[ $OS == 'fedora' ]]; then
            dnf install -y openvpn iptables openssl wget ca-certificates curl policycoreutils-python-utils
        elif [[ $OS == 'arch' ]]; then
            pacman --needed --noconfirm -Syu openvpn iptables openssl wget ca-certificates curl
        fi
        if [[ -d /etc/openvpn/easy-rsa/ ]]; then
            rm -rf /etc/openvpn/easy-rsa/
        fi
    fi

    # Determine the permissionless group
    if grep -qs "^nogroup:" /etc/group; then
        NOGROUP=nogroup
    else
        NOGROUP=nobody
    fi

    # Install easy-rsa if not already present with version selection
    if [[ ! -d /etc/openvpn/easy-rsa/ ]]; then
        # Check if curl is installed, install it if not
        if ! command -v curl >/dev/null 2>&1; then
            echo "curl is required but not installed. Installing curl..."
            if [[ $OS =~ (debian|ubuntu) ]]; then
                apt-get update && apt-get install -y curl
            elif [[ $OS =~ (centos|amzn|oracle) ]]; then
                yum install -y curl
            elif [[ $OS == 'fedora' ]]; then
                dnf install -y curl
            elif [[ $OS == 'arch' ]]; then
                pacman -Syu --noconfirm curl
            fi
            if ! command -v curl >/dev/null 2>&1; then
                echo "Failed to install curl. Aborting."
                exit 1
            fi
        fi

        # Check latest easy-rsa version from GitHub
        latest_version=$(curl -s https://api.github.com/repos/OpenVPN/easy-rsa/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
        if [[ -z "$latest_version" ]]; then
            echo "Failed to fetch the latest easy-rsa version from GitHub. Defaulting to 3.1.2."
            latest_version="3.1.2"
        fi

        # Ask user whether to use the latest version or 3.1.2
        echo ""
        echo "Which version of easy-rsa do you want to install?"
        echo "   1) Latest version from GitHub: $latest_version (recommended)"
        echo "   2) Version 3.1.2"
        until [[ $EASYRSA_VERSION_CHOICE =~ ^[1-2]$ ]]; do
            read -rp "Version choice [1-2]: " -e -i 1 EASYRSA_VERSION_CHOICE
        done

        case $EASYRSA_VERSION_CHOICE in
            1)
                local version="$latest_version"
                echo "Using latest easy-rsa version: $version"
                ;;
            2)
                local version="3.1.2"
                echo "Using easy-rsa version: $version"
                ;;
        esac

        wget -O ~/easy-rsa.tgz https://github.com/OpenVPN/easy-rsa/releases/download/v${version}/EasyRSA-${version}.tgz
        mkdir -p /etc/openvpn/easy-rsa
        tar xzf ~/easy-rsa.tgz --strip-components=1 --no-same-owner --directory /etc/openvpn/easy-rsa
        rm -f ~/easy-rsa.tgz

        cd /etc/openvpn/easy-rsa/ || return
        case $CERT_TYPE in
            1)
                echo "set_var EASYRSA_ALGO ec" >vars
                echo "set_var EASYRSA_CURVE $CERT_CURVE" >>vars
                ;;
            2)
                echo "set_var EASYRSA_KEY_SIZE $RSA_KEY_SIZE" >vars
                ;;
        esac

        # Generate random server identifiers
        SERVER_CN="cn_$(head /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)"
        echo "$SERVER_CN" >SERVER_CN_GENERATED
        SERVER_NAME="server"
        echo "$SERVER_NAME" >SERVER_NAME_GENERATED

        # Create PKI and certificates
        ./easyrsa init-pki
        EASYRSA_CA_EXPIRE=3650 ./easyrsa --batch --req-cn="$SERVER_CN" build-ca nopass

        if [[ $DH_TYPE == "2" ]]; then
            openssl dhparam -out dh.pem $DH_KEY_SIZE
        fi

        EASYRSA_CERT_EXPIRE=3650 ./easyrsa --batch build-server-full "$SERVER_NAME" nopass
        EASYRSA_CRL_DAYS=3650 ./easyrsa gen-crl

        case $TLS_SIG in
            1) openvpn --genkey --secret /etc/openvpn/tls-crypt.key ;;
            2) openvpn --genkey --secret /etc/openvpn/tls-auth.key ;;
        esac
    else
        cd /etc/openvpn/easy-rsa/ || return
        SERVER_NAME=$(cat SERVER_NAME_GENERATED)
    fi

    # Copy generated files
    cp pki/ca.crt pki/private/ca.key "pki/issued/$SERVER_NAME.crt" "pki/private/$SERVER_NAME.key" /etc/openvpn/easy-rsa/pki/crl.pem /etc/openvpn
    if [[ $DH_TYPE == "2" ]]; then
        cp dh.pem /etc/openvpn
    fi

    chmod 644 /etc/openvpn/crl.pem

    # Create server configuration
    echo "port $PORT" >/etc/openvpn/server.conf
    if [[ $IPV6_SUPPORT == 'n' ]]; then
        echo "proto $PROTOCOL" >>/etc/openvpn/server.conf
    elif [[ $IPV6_SUPPORT == 'y' ]]; then
        echo "proto ${PROTOCOL}6" >>/etc/openvpn/server.conf
    fi

    echo "dev tun
user nobody
group $NOGROUP
persist-key
persist-tun
keepalive 10 120
topology subnet
server ${IPVPN}.0 255.255.255.0
ifconfig-pool-persist ipp.txt" >>/etc/openvpn/server.conf

    # IPv6 settings if enabled
    if [[ $IPV6_SUPPORT == 'y' ]]; then
        echo 'server-ipv6 fd42:42:42:42::/112
tun-ipv6
push tun-ipv6
push "route-ipv6 2000::/3"
push "redirect-gateway ipv6"' >>/etc/openvpn/server.conf
    fi

    if [[ $COMPRESSION_ENABLED == "y" ]]; then
        echo "compress $COMPRESSION_ALG" >>/etc/openvpn/server.conf
    fi

    if [[ $DH_TYPE == "1" ]]; then
        echo "dh none" >>/etc/openvpn/server.conf
        echo "ecdh-curve $DH_CURVE" >>/etc/openvpn/server.conf
    elif [[ $DH_TYPE == "2" ]]; then
        echo "dh dh.pem" >>/etc/openvpn/server.conf
    fi

    case $TLS_SIG in
        1) echo "tls-crypt tls-crypt.key" >>/etc/openvpn/server.conf ;;
        2) echo "tls-auth tls-auth.key 0" >>/etc/openvpn/server.conf ;;
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
verb 3" >>/etc/openvpn/server.conf

    # Create directories and _default file
    mkdir -p /etc/openvpn/ccd
    touch /etc/openvpn/ccd/_default
    mkdir -p /var/log/openvpn

    # Enable routing
    echo 'net.ipv4.ip_forward=1' >/etc/sysctl.d/99-openvpn.conf
    if [[ $IPV6_SUPPORT == 'y' ]]; then
        echo 'net.ipv6.conf.all.forwarding=1' >>/etc/sysctl.d/99-openvpn.conf
    fi
    sysctl --system

    # Configure SELinux for custom port
    if hash sestatus 2>/dev/null; then
        if sestatus | grep "Current mode" | grep -qs "enforcing"; then
            if [[ $PORT != '1194' ]]; then
                semanage port -a -t openvpn_port_t -p "$PROTOCOL" "$PORT"
            fi
        fi
    fi

    # Restart and enable OpenVPN
    if [[ $OS == 'arch' || $OS == 'fedora' || $OS == 'centos' || $OS == 'oracle' ]]; then
        cp /usr/lib/systemd/system/openvpn-server@.service /etc/systemd/system/openvpn-server@.service
        sed -i 's|LimitNPROC|#LimitNPROC|' /etc/systemd/system/openvpn-server@.service
        sed -i 's|/etc/openvpn/server|/etc/openvpn|' /etc/systemd/system/openvpn-server@.service
        systemctl daemon-reload
        systemctl enable openvpn-server@server
        systemctl restart openvpn-server@server
    elif [[ $OS == "ubuntu" ]] && [[ $VERSION_ID == "16.04" ]]; then
        systemctl enable openvpn
        systemctl start openvpn
    else
        cp /lib/systemd/system/openvpn\@.service /etc/systemd/system/openvpn\@.service
        sed -i 's|LimitNPROC|#LimitNPROC|' /etc/systemd/system/openvpn\@.service
        sed -i 's|/etc/openvpn/server|/etc/openvpn|' /etc/systemd/system/openvpn\@.service
        systemctl daemon-reload
        systemctl enable openvpn@server
        systemctl restart openvpn@server
    fi

    # Add iptables rules
    mkdir -p /etc/iptables
    echo "#!/bin/sh
iptables -t nat -I POSTROUTING 1 -s ${IPVPN}.0/24 -o $NIC -j MASQUERADE
iptables -I INPUT 1 -i tun0 -j ACCEPT
iptables -I FORWARD 1 -i $NIC -o tun0 -j ACCEPT
iptables -I FORWARD 1 -i tun0 -o $NIC -j ACCEPT
iptables -I INPUT 1 -i $NIC -p $PROTOCOL --dport $PORT -j ACCEPT" >/etc/iptables/add-openvpn-rules.sh

    if [[ $IPV6_SUPPORT == 'y' ]]; then
        echo "ip6tables -t nat -I POSTROUTING 1 -s fd42:42:42:42::/112 -o $NIC -j MASQUERADE
ip6tables -I INPUT 1 -i tun0 -j ACCEPT
ip6tables -I FORWARD 1 -i $NIC -o tun0 -j ACCEPT
ip6tables -I FORWARD 1 -i tun0 -o $NIC -j ACCEPT
ip6tables -I INPUT 1 -i $NIC -p $PROTOCOL --dport $PORT -j ACCEPT" >>/etc/iptables/add-openvpn-rules.sh
    fi

    echo "#!/bin/sh
iptables -t nat -D POSTROUTING -s ${IPVPN}.0/24 -o $NIC -j MASQUERADE
iptables -D INPUT -i tun0 -j ACCEPT
iptables -D FORWARD -i $NIC -o tun0 -j ACCEPT
iptables -D FORWARD -i tun0 -o $NIC -j ACCEPT
iptables -D INPUT -i $NIC -p $PROTOCOL --dport $PORT -j ACCEPT" >/etc/iptables/rm-openvpn-rules.sh

    if [[ $IPV6_SUPPORT == 'y' ]]; then
        echo "ip6tables -t nat -D POSTROUTING -s fd42:42:42:42::/112 -o $NIC -j MASQUERADE
ip6tables -D INPUT -i tun0 -j ACCEPT
ip6tables -D FORWARD -i $NIC -o tun0 -j ACCEPT
ip6tables -D FORWARD -i tun0 -o $NIC -j ACCEPT
ip6tables -D INPUT -i $NIC -p $PROTOCOL --dport $PORT -j ACCEPT" >>/etc/iptables/rm-openvpn-rules.sh
    fi

    chmod +x /etc/iptables/add-openvpn-rules.sh
    chmod +x /etc/iptables/rm-openvpn-rules.sh

    # Configure systemd for iptables
    echo "[Unit]
Description=iptables rules for OpenVPN
Before=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/etc/iptables/add-openvpn-rules.sh
ExecStop=/etc/iptables/rm-openvpn-rules.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target" >/etc/systemd/system/iptables-openvpn.service

    systemctl daemon-reload
    systemctl enable iptables-openvpn
    systemctl start iptables-openvpn

    if [[ $ENDPOINT != "" ]]; then
        IP=$ENDPOINT
    fi

    # Create client template
    echo "client" >/etc/openvpn/client-template.txt
    if [[ $PROTOCOL == 'udp' ]]; then
        echo "proto udp" >>/etc/openvpn/client-template.txt
        echo "explicit-exit-notify" >>/etc/openvpn/client-template.txt
    elif [[ $PROTOCOL == 'tcp' ]]; then
        echo "proto tcp-client" >>/etc/openvpn/client-template.txt
    fi
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
verb 3" >>/etc/openvpn/client-template.txt

    if [[ $COMPRESSION_ENABLED == "y" ]]; then
        echo "compress $COMPRESSION_ALG" >>/etc/openvpn/client-template.txt
    fi

    # Generate client configuration
    newClient
    echo "If you want to add more clients, simply run this script again!"
}

# Function to create a new client (always without password)
function newClient() {
    echo ""
    echo "Specify a name for the client."
    echo "The name must consist of alphanumeric characters. It may also include an underscore or a dash."

    until [[ $CLIENT =~ ^[a-zA-Z0-9_-]+$ ]]; do
        read -rp "Client name: " -e CLIENT
    done

    CLIENTEXISTS=$(tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt | grep -c -E "/CN=$CLIENT\$")
    if [[ $CLIENTEXISTS == '1' ]]; then
        echo ""
        echo "The specified client name already exists in easy-rsa. Please choose another name."
        exit
    else
        cd /etc/openvpn/easy-rsa/ || return
        EASYRSA_CERT_EXPIRE=3650 ./easyrsa --batch build-client-full "$CLIENT" nopass
        echo "Client $CLIENT added."
    fi

    # Set fixed directory and create it if it doesn't exist
    homeDir="/etc/openvpn/_OpenVPN_KEY"
    if [ ! -d "$homeDir" ]; then
        mkdir -p "$homeDir"
    fi

    if grep -qs "^tls-crypt" /etc/openvpn/server.conf; then
        TLS_SIG="1"
    elif grep -qs "^tls-auth" /etc/openvpn/server.conf; then
        TLS_SIG="2"
    fi

    # Generate client configuration file
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
    echo "Download the .ovpn file and import it into your OpenVPN client."
    echo "...Copying _default CCD for $CLIENT..."
    cp /etc/openvpn/ccd/_default /etc/openvpn/ccd/$CLIENT
    cat /etc/openvpn/ccd/$CLIENT
    echo "------------------------------------------------------------------------------"

    exit 0
}

# Function to revoke a client
function revokeClient() {
    NUMBEROFCLIENTS=$(tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt | grep -c "^V")
    if [[ $NUMBEROFCLIENTS == '0' ]]; then
        echo ""
        echo "You have no existing clients!"
        exit 1
    fi

    echo ""
    echo "Select the existing client certificate to revoke:"
    tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt | grep "^V" | cut -d '=' -f 2 | nl -s ') '
    until [[ $CLIENTNUMBER -ge 1 && $CLIENTNUMBER -le $NUMBEROFCLIENTS ]]; do
        if [[ $CLIENTNUMBER == '1' ]]; then
            read -rp "Select one client [1]: " CLIENTNUMBER
        else
            read -rp "Select one client [1-$NUMBEROFCLIENTS]: " CLIENTNUMBER
        fi
    done
    CLIENT=$(tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt | grep "^V" | cut -d '=' -f 2 | sed -n "$CLIENTNUMBER"p)
    cd /etc/openvpn/easy-rsa/ || return
    ./easyrsa --batch revoke "$CLIENT"
    EASYRSA_CRL_DAYS=3650 ./easyrsa gen-crl
    rm -f /etc/openvpn/crl.pem
    cp /etc/openvpn/easy-rsa/pki/crl.pem /etc/openvpn/crl.pem
    chmod 644 /etc/openvpn/crl.pem
    rm -f "/etc/openvpn/_OpenVPN_KEY/$CLIENT.ovpn"  # Remove only from the fixed directory
    sed -i "/^$CLIENT,.*/d" /etc/openvpn/ipp.txt
    cp /etc/openvpn/easy-rsa/pki/index.txt{,.bk}
    rm -f /etc/openvpn/ccd/$CLIENT
    echo ""
    echo "Certificate for client $CLIENT revoked."
}

# Function to remove OpenVPN
function removeOpenVPN() {
    echo ""
    read -rp "Do you really want to remove OpenVPN? [y/n]: " -e -i n REMOVE
    if [[ $REMOVE == 'y' ]]; then
        PORT=$(grep '^port ' /etc/openvpn/server.conf | cut -d " " -f 2)
        PROTOCOL=$(grep '^proto ' /etc/openvpn/server.conf | cut -d " " -f 2)

        if [[ $OS =~ (fedora|arch|centos|oracle) ]]; then
            systemctl disable openvpn-server@server
            systemctl stop openvpn-server@server
            rm /etc/systemd/system/openvpn-server@.service
        elif [[ $OS == "ubuntu" ]] && [[ $VERSION_ID == "16.04" ]]; then
            systemctl disable openvpn
            systemctl stop openvpn
        else
            systemctl disable openvpn@server
            systemctl stop openvpn@server
            rm /etc/systemd/system/openvpn\@.service
        fi

        systemctl stop iptables-openvpn
        systemctl disable iptables-openvpn
        rm /etc/systemd/system/iptables-openvpn.service
        systemctl daemon-reload
        rm /etc/iptables/add-openvpn-rules.sh
        rm /etc/iptables/rm-openvpn-rules.sh

        if hash sestatus 2>/dev/null; then
            if sestatus | grep "Current mode" | grep -qs "enforcing"; then
                if [[ $PORT != '1194' ]]; then
                    semanage port -d -t openvpn_port_t -p "$PROTOCOL" "$PORT"
                fi
            fi
        fi

        if [[ $OS =~ (debian|ubuntu) ]]; then
            apt-get remove --purge -y openvpn
            if [[ -e /etc/apt/sources.list.d/openvpn.list ]]; then
                rm /etc/apt/sources.list.d/openvpn.list
                apt-get update
            fi
        elif [[ $OS == 'arch' ]]; then
            pacman --noconfirm -R openvpn
        elif [[ $OS =~ (centos|amzn|oracle) ]]; then
            yum remove -y openvpn
        elif [[ $OS == 'fedora' ]]; then
            dnf remove -y openvpn
        fi

        find /home/ -maxdepth 2 -name "*.ovpn" -delete
        find /root/ -maxdepth 1 -name "*.ovpn" -delete
        rm -rf /etc/openvpn
        rm -rf /usr/share/doc/openvpn*
        rm -f /etc/sysctl.d/99-openvpn.conf
        rm -rf /var/log/openvpn

        rm -rf  /usr/local/bin/vpn-stat
        rm -rf /usr/local/bin/vpn-user

        echo ""
        echo "OpenVPN removed!"
    else
        echo ""
        echo "Removal aborted!"
    fi
}

# Function to manage menu
function manageMenu() {
    echo "Welcome to OpenVPN-install!"
    echo "The Git repository is available at: https://github.com/angristan/openvpn-install"
    echo ""
    echo "It looks like OpenVPN is already installed."
    echo ""
    echo "What do you want to do?"
    echo "   1) Add a new user"
    echo "   2) Revoke an existing user"
    echo "   3) Remove OpenVPN"
    echo "   4) Exit"
    until [[ $MENU_OPTION =~ ^[1-4]$ ]]; do
        read -rp "Select an option [1-4]: " MENU_OPTION
    done

    case $MENU_OPTION in
        1) newClient ;;
        2) revokeClient ;;
        3) removeOpenVPN ;;
        4) exit 0 ;;
    esac
}

# Perform initial check
initialCheck

# Check if OpenVPN is already installed
if [[ -e /etc/openvpn/server.conf && $AUTO_INSTALL != "y" ]]; then
    manageMenu
else
    installOpenVPN
fi
