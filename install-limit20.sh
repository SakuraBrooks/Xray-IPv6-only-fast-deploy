#!/usr/bin/env bash
set -euo pipefail

cat > /usr/local/sbin/net-limit.sh <<'EOF'
#!/bin/bash
set -e

modprobe ifb

ip link add ifb0 type ifb 2>/dev/null || true
ip link set ifb0 up

tc qdisc replace dev enp1s0 root tbf rate 20mbit burst 64kb latency 400ms

tc qdisc replace dev enp1s0 handle ffff: ingress
tc filter del dev enp1s0 parent ffff: 2>/dev/null || true
tc filter add dev enp1s0 parent ffff: protocol all pref 1 matchall action mirred egress redirect dev ifb0

tc qdisc replace dev ifb0 root tbf rate 20mbit burst 64kb latency 400ms
EOF

chmod +x /usr/local/sbin/net-limit.sh

cat > /etc/systemd/system/net-limit.service <<'EOF'
[Unit]
Description=Limit whole NIC bandwidth
After=network-online.target sys-subsystem-net-devices-enp1s0.device
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/net-limit.sh

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now net-limit

echo "20Mbps limit installed successfully."
