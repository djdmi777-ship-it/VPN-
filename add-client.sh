#!/bin/bash
# Добавляет нового клиента к уже настроенному WireGuard-серверу.
# Использование: sudo ./add-client.sh mylaptop

set -e

if [ "$EUID" -ne 0 ]; then
  echo "Запусти скрипт от root: sudo ./add-client.sh <имя>"
  exit 1
fi

if [ -z "$1" ]; then
  echo "Укажи имя клиента, например: ./add-client.sh mylaptop"
  exit 1
fi

CLIENT_NAME=$1
WG_IFACE="wg0"
WG_PORT=51820
CLIENTS_DIR="/etc/wireguard/clients"
mkdir -p ${CLIENTS_DIR}

# следующий свободный IP в подсети 10.66.66.0/24 (сервер занимает .1)
LAST_OCTET=$(grep -oP '10\.66\.66\.\K[0-9]+' /etc/wireguard/${WG_IFACE}.conf | sort -n | tail -1)
LAST_OCTET=${LAST_OCTET:-1}
NEXT_OCTET=$((LAST_OCTET + 1))
CLIENT_IP="10.66.66.${NEXT_OCTET}/32"
CLIENT_IP6="fd66:66:66::${NEXT_OCTET}/128"

umask 077
CLIENT_PRIV=$(wg genkey)
CLIENT_PUB=$(echo "${CLIENT_PRIV}" | wg pubkey)

SERVER_PUB_KEY=$(cat /etc/wireguard/server_public.key)
SERVER_PUB_IP=$(curl -s -4 ifconfig.me)

# добавляем peer в конфиг сервера
cat >> /etc/wireguard/${WG_IFACE}.conf <<EOF
[Peer]
# ${CLIENT_NAME}
PublicKey = ${CLIENT_PUB}
AllowedIPs = ${CLIENT_IP}, ${CLIENT_IP6}
EOF

wg syncconf ${WG_IFACE} <(wg-quick strip ${WG_IFACE})

# конфиг для клиента
CLIENT_CONF="${CLIENTS_DIR}/${CLIENT_NAME}.conf"
cat > ${CLIENT_CONF} <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIV}
MTU = 1280
Address = ${CLIENT_IP}, ${CLIENT_IP6}
DNS = 1.1.1.1

[Peer]
PublicKey = ${SERVER_PUB_KEY}
Endpoint = ${SERVER_PUB_IP}:${WG_PORT}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

echo ""
echo "===================================================="
echo "Клиент '${CLIENT_NAME}' добавлен."
echo "Конфиг сохранён: ${CLIENT_CONF}"
echo ""
echo "Скопируй его к себе на комп командой, например:"
echo "  scp root@${SERVER_PUB_IP}:${CLIENT_CONF} ."
echo ""
echo "Или отсканируй QR-код телефоном:"
qrencode -t ansiutf8 < ${CLIENT_CONF}
echo "===================================================="
