IFACE=$(ip route show default | awk '/default/ {print $5; exit}')
[ -z "$IFACE" ] && IFACE=$(ip -o link show up | awk -F': ' '$2 != "lo" {print $2; exit}')
[ -z "$IFACE" ] && exit 1

cat > /usr/local/sbin/net-limit.sh <<EOF
#!/bin/bash
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

if command -v systemctl >/dev/null; then
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
  systemctl daemon-reload
  systemctl enable --now net-limit
elif command -v rc-service >/dev/null; then
  cat > /etc/init.d/net-limit <<'EOF'
#!/sbin/openrc-run
description="Limit whole NIC bandwidth"
depend() {
    need net
    after firewall
}
start() {
    /usr/local/sbin/net-limit.sh
}
stop() {
    return 0
}
EOF
  chmod +x /etc/init.d/net-limit
  rc-update add net-limit default
  rc-service net-limit start
else
  [ ! -f /etc/rc.local ] && printf '#!/bin/sh -e\nexit 0\n' > /etc/rc.local && chmod +x /etc/rc.local
  grep -q '/usr/local/sbin/net-limit.sh' /etc/rc.local || sed -i '/^exit 0/i /usr/local/sbin/net-limit.sh' /etc/rc.local
  /usr/local/sbin/net-limit.sh
fi
