#!/usr/bin/env bash
# ============================================================
# This script applies a 20Mbps bandwidth limit to the whole
# network interface (both IPv4 and IPv6 traffic).
# The interface is auto-detected.
# Core tc/ifb logic is unchanged.
# ============================================================

set -euo pipefail

log() {
  local level="$1"; shift
  local ts
  ts=$(date +"%b %d %H:%M:%S.%3N" 2>/dev/null || date +"%b %d %H:%M:%S")
  printf "%s [%s] %s\n" "$ts" "$level" "$*" >&2
}

trap 'log "error" "Fail"; exit 1' ERR

# Detect default network interface
IFACE=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
if [ -z "$IFACE" ]; then
  IFACE=$(ip -o link show up 2>/dev/null | awk -F': ' '$2 != "lo" {print $2; exit}')
fi
if [ -z "$IFACE" ]; then
  log "error" "Could not detect network interface"
  exit 1
fi

log "notice" "Detected interface: ${IFACE}"

# Create the limit script (core logic unchanged)
cat > /usr/local/sbin/net-limit.sh <<EOF
#!/bin/bash
set -e

modprobe ifb

ip link add ifb0 type ifb 2>/dev/null || true
ip link set ifb0 up

tc qdisc replace dev ${IFACE} root tbf rate 20mbit burst 64kb latency 400ms

tc qdisc replace dev ${IFACE} handle ffff: ingress
tc filter del dev ${IFACE} parent ffff: 2>/dev/null || true
tc filter add dev ${IFACE} parent ffff: protocol all pref 1 matchall action mirred egress redirect dev ifb0

tc qdisc replace dev ifb0 root tbf rate 20mbit burst 64kb latency 400ms
EOF

chmod +x /usr/local/sbin/net-limit.sh

# Install service based on init system
if command -v systemctl >/dev/null 2>&1; then
  cat > /etc/systemd/system/net-limit.service <<EOF
[Unit]
Description=Limit whole NIC bandwidth
After=network-online.target sys-subsystem-net-devices-${IFACE}.device
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/net-limit.sh

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload >/dev/null 2>&1
  systemctl enable --now net-limit >/dev/null 2>&1
  log "notice" "Installed systemd service: net-limit"

elif command -v rc-service >/dev/null 2>&1; then
  cat > /etc/init.d/net-limit <<'EOF'
#!/sbin/openrc-run

description="Limit whole NIC bandwidth"

depend() {
    need net
    after firewall
}

start() {
    ebegin "Starting net-limit"
    /usr/local/sbin/net-limit.sh
    eend $?
}

stop() {
    ebegin "Stopping net-limit"
    eend 0
}
EOF
  chmod +x /etc/init.d/net-limit
  rc-update add net-limit default >/dev/null 2>&1
  rc-service net-limit start >/dev/null 2>&1
  log "notice" "Installed OpenRC service: net-limit"

else
  # Fallback: use /etc/rc.local
  if [ ! -f /etc/rc.local ]; then
    printf '#!/bin/sh -e\nexit 0\n' > /etc/rc.local
    chmod +x /etc/rc.local
  fi
  if ! grep -q '/usr/local/sbin/net-limit.sh' /etc/rc.local; then
    sed -i '/^exit 0/i /usr/local/sbin/net-limit.sh' /etc/rc.local
  fi
  /usr/local/sbin/net-limit.sh >/dev/null 2>&1
  log "warn" "No systemd/OpenRC found; used /etc/rc.local fallback"
fi

log "notice" "20Mbps limit installed successfully."
