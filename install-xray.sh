#!/usr/bin/env bash

set -euo pipefail

need_cmd() { command -v "$1" >/dev/null 2>&1; }

trap 'exit 1' ERR

curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh | bash -s @ install

UUID=$(xray uuid)
KEYS=$(xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | grep -i private | awk '{print $NF}')
PUBLIC_KEY=$(echo "$KEYS" | grep -i public | awk '{print $NF}')

if need_cmd openssl; then
  SHORT_ID=$(openssl rand -hex 4)
else
  SHORT_ID=$(dd if=/dev/urandom bs=4 count=1 2>/dev/null | od -An -tx1 | tr -d '[:space:]')
fi

mkdir -p /usr/local/etc/xray

cat >/usr/local/etc/xray/config.json <<EOF
{
  "log": { "loglevel": "none" },
  "dns": {
    "servers": [
      "2001:4860:4860::8888",
      "2001:4860:4860::8844"
    ]
  },
  "policy": {
    "levels": {
      "0": { "connIdle": 300 }
    }
  },
  "inbounds": [
    {
      "listen": "::",
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [ { "id": "${UUID}", "level": 0 } ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "xhttpSettings": {
          "path": "/content/downloads/33/54/041-2011/pRtCDYcWShMLxFggy3TzFzmfnnWQNFQBfJ/BootCampESD.pkg",
          "mode": "stream-one"
        },
        "security": "reality",
        "realitySettings": {
          "target": "swcdn.apple.com:443",
          "serverNames": ["swcdn.apple.com"],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": ["${SHORT_ID}"],
          "show": false
        },
        "sockopt": {
          "v6only": true
        }
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": { "domainStrategy": "UseIPv6v4" }
    }
  ]
}
EOF

xray run -test -c /usr/local/etc/xray/config.json

if need_cmd systemctl; then
  systemctl enable xray
  systemctl restart xray
elif need_cmd rc-service; then
  rc-service xray restart
elif need_cmd service; then
  service xray restart
else
  exit 1
fi

if need_cmd ufw; then
  ufw allow 443/tcp
elif need_cmd firewall-cmd; then
  firewall-cmd --permanent --add-port=443/tcp
  firewall-cmd --reload
elif need_cmd iptables; then
  iptables -I INPUT -p tcp --dport 443 -j ACCEPT
else
  exit 1
fi

IP=$(curl -6 --max-time 6 ip.sb || curl -6 --max-time 6 ifconfig.co)
NODE_NAME="$(hostname)-$(date +%m%d)"

if [[ "$IP" == *:* ]]; then
  HOST="[${IP}]"
else
  HOST="${IP}"
fi

LINK="vless://${UUID}@${HOST}:443?encryption=none&security=reality&sni=swcdn.apple.com&fp=firefox&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=xhttp&path=%2Fcontent%2Fdownloads%2F33%2F54%2F041-2011%2FpRtCDYcWShMLxFggy3TzFzmfnnWQNFQBfJ%2FBootCampESD.pkg&mode=stream-one#${NODE_NAME}"

echo "$LINK"
