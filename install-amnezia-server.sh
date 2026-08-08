#!/bin/bash
# Установка AmneziaWG (обфусцированный WireGuard) рядом с обычным wg0.
# Нужен, когда обычный WireGuard блокируется DPI провайдера.
# Запускать от root на Ubuntu/Debian с уже установленным пакетом amneziawg-tools.
# Использование: ./install-amnezia-server.sh

set -e

if [ "$EUID" -ne 0 ]; then
  echo "Запусти скрипт от root: sudo ./install-amnezia-server.sh"
  exit 1
fi

AWG_PORT=51821
AWG_IFACE="awg0"
AWG_SUBNET="10.77.77.1/24"
AWG_SUBNET6="fd77:77:77::1/64"
AWG_DIR="/etc/amnezia/amneziawg"

echo "==> Определяю внешний сетевой интерфейс..."
PUB_IFACE=$(ip route get 8.8.8.8 | awk '{print $5; exit}')
echo "Внешний интерфейс: $PUB_IFACE"

echo "==> Проверяю модуль ядра..."
modprobe amneziawg

mkdir -p ${AWG_DIR}
chmod 700 ${AWG_DIR}

echo "==> Генерирую ключи сервера..."
umask 077
awg genkey | tee ${AWG_DIR}/server_private.key | awg pubkey > ${AWG_DIR}/server_public.key
SERVER_PRIV=$(cat ${AWG_DIR}/server_private.key)

echo "==> Генерирую параметры обфускации (H1-H4)..."
H1=$(od -An -N4 -tu4 /dev/urandom | tr -d ' ')
H2=$(od -An -N4 -tu4 /dev/urandom | tr -d ' ')
H3=$(od -An -N4 -tu4 /dev/urandom | tr -d ' ')
H4=$(od -An -N4 -tu4 /dev/urandom | tr -d ' ')
echo "${H1} ${H2} ${H3} ${H4}" > ${AWG_DIR}/obfuscation_params.txt

echo "==> Создаю конфиг сервера..."
cat > ${AWG_DIR}/${AWG_IFACE}.conf <<EOF
[Interface]
Address = ${AWG_SUBNET}, ${AWG_SUBNET6}
ListenPort = ${AWG_PORT}
PrivateKey = ${SERVER_PRIV}
MTU = 1280
Jc = 4
Jmin = 40
Jmax = 70
S1 = 68
S2 = 88
H1 = ${H1}
H2 = ${H2}
H3 = ${H3}
H4 = ${H4}
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o ${PUB_IFACE} -j MASQUERADE; iptables -t mangle -A FORWARD -o %i -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu; ip6tables -A FORWARD -i %i -j ACCEPT; ip6tables -t nat -A POSTROUTING -o ${PUB_IFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o ${PUB_IFACE} -j MASQUERADE; iptables -t mangle -D FORWARD -o %i -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu; ip6tables -D FORWARD -i %i -j ACCEPT; ip6tables -t nat -D POSTROUTING -o ${PUB_IFACE} -j MASQUERADE
EOF
chmod 600 ${AWG_DIR}/${AWG_IFACE}.conf

echo "==> Включаю форвардинг (на случай если ещё не включён)..."
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
sed -i 's/#net.ipv6.conf.all.forwarding=1/net.ipv6.conf.all.forwarding=1/' /etc/sysctl.conf
grep -q '^net.ipv6.conf.all.forwarding=1' /etc/sysctl.conf || echo 'net.ipv6.conf.all.forwarding=1' >> /etc/sysctl.conf
sysctl -p

echo "==> Открываю порт в ufw (если используется)..."
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  ufw allow ${AWG_PORT}/udp
fi

echo "==> Запускаю awg0..."
awg-quick up ${AWG_IFACE}
systemctl enable awg-quick@${AWG_IFACE}

echo ""
echo "===================================================="
echo "AmneziaWG сервер запущен на порту ${AWG_PORT}/udp."
echo "Публичный ключ сервера:"
cat ${AWG_DIR}/server_public.key
echo "===================================================="
