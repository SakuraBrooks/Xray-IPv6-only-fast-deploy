#!/usr/bin/env bash
# ============================================================
# WARNING: This script is intended for IPv6-only VPS.
# It listens on IPv6 (::) and uses IPv6 for all connectivity.
# Before running, make sure you have installed fscarmen's
# WARP script to provide IPv4 outbound if your VPS needs to
# reach IPv4-only resources. Otherwise, some destinations may
# be unreachable.
#
# fscarmen's WARP script (latest, GitLab):
#   wget -N https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh && bash menu.sh
#
# The old GitHub repository (fscarmen/warp-sh) has been moved
# to GitLab. See: https://gitlab.com/fscarmen/warp
# ============================================================

set -euo pipefail

need_cmd() { command -v "$1" >/dev/null 2>&1; }

log() {
  local level="$1"; shift
  local ts
  ts=$(date +"%b %d %H:%M:%S.%3N" 2>/dev/null || date +"%b %d %H:%M:%S")
  printf "%s [%s] %s\n" "$ts" "$level" "$*" >&2
}

trap 'log "error" "Fail"; exit 1' ERR

# Install Xray quietly
INSTALL_SH=$(curl -sL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)
bash -c "$INSTALL_SH" @ install >/dev/null 2>&1

UUID=$(xray uuid)
KEYS=$(xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | grep -i private | awk '{print $NF}')
PUBLIC_KEY=$(echo "$KEYS" | grep -i public | awk '{print $NF}')

# Generate short ID
if need_cmd openssl; then
  SHORT_ID=$(openssl rand -hex 4)
else
  SHORT_ID=$(dd if=/dev/urandom bs=4 count=1 2>/dev/null | od -An -tx1 | tr -d '[:space:]')
fi

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

# Test config quietly
TEST_OUT=$(xray run -test -c /usr/local/etc/xray/config.json 2>&1) || true
if ! grep -q "Configuration OK" <<<"$TEST_OUT"; then
  log "error" "Fail"
  exit 1
fi

# Start service quietly
if need_cmd systemctl; then
  systemctl enable xray >/dev/null 2>&1
  systemctl restart xray >/dev/null 2>&1
elif need_cmd rc-service; then
  rc-service xray restart >/dev/null 2>&1
elif need_cmd service; then
  service xray restart >/dev/null 2>&1
else
  log "error" "No supported service manager found"
  exit 1
fi

# Open port quietly
if need_cmd ufw; then
  ufw allow 443/tcp >/dev/null 2>&1
elif need_cmd firewall-cmd; then
  firewall-cmd --permanent --add-port=443/tcp >/dev/null 2>&1
  firewall-cmd --reload >/dev/null 2>&1
elif need_cmd iptables; then
  iptables -I INPUT -p tcp --dport 443 -j ACCEPT >/dev/null 2>&1
else
  log "warn" "No supported firewall tool found; make sure 443/tcp is open."
fi

IP=$(curl -s6 --max-time 6 ip.sb || curl -s6 --max-time 6 ifconfig.co)
NODE_NAME="$(hostname)-$(date +%m%d)"

if [[ "$IP" == *:* ]]; then
  HOST="[${IP}]"
else
  HOST="${IP}"
fi

LINK="vless://${UUID}@${HOST}:443?encryption=none&security=reality&sni=swcdn.apple.com&fp=firefox&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=xhttp&path=%2Fcontent%2Fdownloads%2F33%2F54%2F041-2011%2FpRtCDYcWShMLxFggy3TzFzmfnnWQNFQBfJ%2FBootCampESD.pkg&mode=stream-one#${NODE_NAME}"

echo "$LINK"
