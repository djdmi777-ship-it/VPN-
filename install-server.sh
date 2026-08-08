#!/bin/bash
# Установка WireGuard-сервера. Запускать от root на Ubuntu/Debian.
# Использование: ./install-server.sh

set -e

if [ "$EUID" -ne 0 ]; then
  echo "Запусти скрипт от root: sudo ./install-server.sh"
  exit 1
fi

WG_PORT=51820
WG_IFACE="wg0"
WG_SUBNET="10.66.66.1/24"
WG_SUBNET6="fd66:66:66::1/64"

echo "==> Определяю внешний сетевой интерфейс..."
PUB_IFACE=$(ip route get 8.8.8.8 | awk '{print $5; exit}')
echo "Внешний интерфейс: $PUB_IFACE"

echo "==> Устанавливаю WireGuard..."
apt update -y
apt install -y wireguard qrencode

echo "==> Включаю форвардинг пакетов..."
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
sed -i 's/#net.ipv6.conf.all.forwarding=1/net.ipv6.conf.all.forwarding=1/' /etc/sysctl.conf
grep -q '^net.ipv6.conf.all.forwarding=1' /etc/sysctl.conf || echo 'net.ipv6.conf.all.forwarding=1' >> /etc/sysctl.conf
sysctl -p

echo "==> Генерирую ключи сервера..."
mkdir -p /etc/wireguard
umask 077
wg genkey | tee /etc/wireguard/server_private.key | wg pubkey > /etc/wireguard/server_public.key
SERVER_PRIV=$(cat /etc/wireguard/server_private.key)

echo "==> Создаю конфиг сервера..."
cat > /etc/wireguard/${WG_IFACE}.conf <<EOF
[Interface]
Address = ${WG_SUBNET}, ${WG_SUBNET6}
ListenPort = ${WG_PORT}
PrivateKey = ${SERVER_PRIV}
MTU = 1280
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o ${PUB_IFACE} -j MASQUERADE; iptables -t mangle -A FORWARD -o %i -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu; ip6tables -A FORWARD -i %i -j ACCEPT; ip6tables -t nat -A POSTROUTING -o ${PUB_IFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o ${PUB_IFACE} -j MASQUERADE; iptables -t mangle -D FORWARD -o %i -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu; ip6tables -D FORWARD -i %i -j ACCEPT; ip6tables -t nat -D POSTROUTING -o ${PUB_IFACE} -j MASQUERADE

EOF

echo "==> Открываю порт в UFW (если используется)..."
if command -v ufw >/dev/null; then
  ufw allow ${WG_PORT}/udp
fi

echo "==> Запускаю сервис..."
systemctl enable wg-quick@${WG_IFACE}
systemctl start wg-quick@${WG_IFACE}

SERVER_PUB_IP=$(curl -s -4 ifconfig.me)
SERVER_PUB_KEY=$(cat /etc/wireguard/server_public.key)

echo ""
echo "===================================================="
echo "Готово! Сервер поднят."
echo "Публичный IP сервера : ${SERVER_PUB_IP}"
echo "Публичный ключ сервера: ${SERVER_PUB_KEY}"
echo "Порт                 : ${WG_PORT}"
echo "===================================================="
echo ""
echo "Дальше запусти ./add-client.sh <имя_клиента> чтобы добавить устройство."
