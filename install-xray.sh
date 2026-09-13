#!/usr/bin/env bash
set -euo pipefail

trap 'printf "\n\033[31mFail\033[0m\n" >&2; exit 1' ERR

bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

UUID=$(xray uuid)
KEYS=$(xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | grep -i private | awk '{print $NF}')
PUBLIC_KEY=$(echo "$KEYS" | grep -i public | awk '{print $NF}')
SHORT_ID=$(openssl rand -hex 4)

mkdir -p /usr/local/etc/xray

cat >/usr/local/etc/xray/config.json <<EOF
{
  "log": { "loglevel": "none" },
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

chmod 600 /usr/local/etc/xray/config.json

TEST_OUT=$(xray run -test -c /usr/local/etc/xray/config.json 2>&1) || true
echo "$TEST_OUT"
if ! grep -q "Configuration OK" <<<"$TEST_OUT"; then
  printf "\n\033[31mFail\033[0m\n" >&2
  exit 1
fi

systemctl enable xray
systemctl restart xray

ufw allow 443/tcp

IP=$(curl -s6 --max-time 6 ip.sb || curl -s6 --max-time 6 ifconfig.co)
NODE_NAME="$(hostname)-$(date +%m%d)"

if [[ "$IP" == *:* ]]; then
  HOST="[${IP}]"
else
  HOST="${IP}"
fi

LINK="vless://${UUID}@${HOST}:443?encryption=none&security=reality&sni=swcdn.apple.com&fp=firefox&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=xhttp&path=%2Fapi%2Fv1%2Fupdates&mode=stream-one#${NODE_NAME}"

clear
echo "$TEST_OUT"
echo
echo
echo
echo "$LINK"
