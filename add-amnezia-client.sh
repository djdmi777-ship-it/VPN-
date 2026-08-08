#!/bin/bash
# Добавляет нового клиента к уже настроенному AmneziaWG-серверу.
# Использование: sudo ./add-amnezia-client.sh mylaptop

set -e

if [ "$EUID" -ne 0 ]; then
  echo "Запусти скрипт от root: sudo ./add-amnezia-client.sh <имя>"
  exit 1
fi

if [ -z "$1" ]; then
  echo "Укажи имя клиента, например: ./add-amnezia-client.sh mylaptop"
  exit 1
fi

CLIENT_NAME=$1
AWG_IFACE="awg0"
AWG_PORT=51821
AWG_DIR="/etc/amnezia/amneziawg"
CLIENTS_DIR="${AWG_DIR}/clients"
mkdir -p ${CLIENTS_DIR}

# следующий свободный IP в подсети 10.77.77.0/24 (сервер занимает .1)
LAST_OCTET=$(grep -oP '10\.77\.77\.\K[0-9]+' ${AWG_DIR}/${AWG_IFACE}.conf | sort -n | tail -1)
LAST_OCTET=${LAST_OCTET:-1}
NEXT_OCTET=$((LAST_OCTET + 1))
CLIENT_IP="10.77.77.${NEXT_OCTET}/32"
CLIENT_IP6="fd77:77:77::${NEXT_OCTET}/128"

umask 077
CLIENT_PRIV=$(awg genkey)
CLIENT_PUB=$(echo "${CLIENT_PRIV}" | awg pubkey)

SERVER_PUB_KEY=$(cat ${AWG_DIR}/server_public.key)
SERVER_PUB_IP=$(curl -s -4 ifconfig.me)
read -r H1 H2 H3 H4 < ${AWG_DIR}/obfuscation_params.txt

# добавляем peer в конфиг сервера
cat >> ${AWG_DIR}/${AWG_IFACE}.conf <<EOF

[Peer]
# ${CLIENT_NAME}
PublicKey = ${CLIENT_PUB}
AllowedIPs = ${CLIENT_IP}, ${CLIENT_IP6}
EOF

awg syncconf ${AWG_IFACE} <(awg-quick strip ${AWG_IFACE})

# конфиг для клиента (приложение AmneziaWG, не обычный WireGuard)
CLIENT_CONF="${CLIENTS_DIR}/${CLIENT_NAME}.conf"
cat > ${CLIENT_CONF} <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIV}
MTU = 1280
Address = ${CLIENT_IP}, ${CLIENT_IP6}
DNS = 1.1.1.1
Jc = 4
Jmin = 40
Jmax = 70
S1 = 68
S2 = 88
H1 = ${H1}
H2 = ${H2}
H3 = ${H3}
H4 = ${H4}

[Peer]
PublicKey = ${SERVER_PUB_KEY}
Endpoint = ${SERVER_PUB_IP}:${AWG_PORT}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

echo ""
echo "===================================================="
echo "Клиент '${CLIENT_NAME}' добавлен (AmneziaWG)."
echo "Конфиг сохранён: ${CLIENT_CONF}"
echo "Импортировать нужно в приложение AmneziaWG (не обычный WireGuard)."
echo ""
qrencode -t ansiutf8 < ${CLIENT_CONF}
echo "===================================================="
