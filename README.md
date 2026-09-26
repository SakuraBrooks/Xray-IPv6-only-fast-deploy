# Xray IPv6-only Fast Deploy

Two standalone shell scripts for quickly deploying Xray on an IPv6-only VPS and applying a 20 Mbps bandwidth limit.

These scripts are tailored to a specific environment. Read the notes below before running.

## Scripts

### `install-xray.sh`

Installs Xray-core and writes a minimal server configuration:

- VLESS inbound listening on `[::]:443`
- REALITY security using `swcdn.apple.com` as the target and SNI
- xhttp transport in `stream-one` mode
- IPv6-only socket option
- Direct outbound with `UseIPv6v4` domain strategy

It also enables and starts the Xray service, opens TCP/443 using the first available firewall tool (`ufw`, `firewalld`, or `iptables`), and prints a `vless://` share link.

### `install-limit20.sh`

Applies a 20 Mbps bandwidth limit to the detected network interface (both ingress and egress) using `tc` and `ifb`. It installs a helper script at `/usr/local/sbin/net-limit.sh` and registers it as a systemd service, OpenRC service, or `/etc/rc.local` entry, depending on the init system.

## Requirements

- A VPS with IPv6 connectivity. The Xray script is intended for IPv6-only hosts.
- IPv4 outbound is **not** provided by these scripts. If your VPS needs to reach IPv4-only destinations, install a WARP script first (for example, fscarmen's).
- Root access.
- A supported init system: systemd, OpenRC, or `/etc/rc.local`.
- Optional firewall tools: `ufw`, `firewalld`, or `iptables`.

## Usage

```bash
# Install Xray
bash install-xray.sh

# Apply 20 Mbps interface limit
bash install-limit20.sh
