#!/usr/bin/env bash

set -Eeuo pipefail
trap 'echo -e "\n[ERROR] in line $LINENO: exit code $?"' ERR

function msg_info() { echo -e " \e[1;36m➤\e[0m $1"; }
function msg_ok() { echo -e " \e[1;32m✔\e[0m $1"; }
function msg_error() { echo -e " \e[1;31m✖\e[0m $1"; }

CTID=$1
CTID_CONFIG_PATH="/etc/pve/lxc/${CTID}.conf"

# Skip if already configured
grep -q "lxc.cgroup2.devices.allow: c 10:200 rwm" "$CTID_CONFIG_PATH" || echo "lxc.cgroup2.devices.allow: c 10:200 rwm" >>"$CTID_CONFIG_PATH"
grep -q "lxc.mount.entry: /dev/net/tun" "$CTID_CONFIG_PATH" || echo "lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file" >>"$CTID_CONFIG_PATH"

msg_info "Installing Tailscale in CT $CTID"

pct exec "$CTID" -- bash -c '
set -e
export DEBIAN_FRONTEND=noninteractive

ID=$(grep "^ID=" /etc/os-release | cut -d"=" -f2)
VER=$(grep "^VERSION_CODENAME=" /etc/os-release | cut -d"=" -f2)

# fallback if DNS is poisoned or blocked
ORIG_RESOLV="/etc/resolv.conf"
BACKUP_RESOLV="/tmp/resolv.conf.backup"

if ! dig +short pkgs.tailscale.com | grep -qvE "^127\.|^0\.0\.0\.0$"; then
  echo "[INFO] DNS resolution for pkgs.tailscale.com failed (blocked or redirected)."
  echo "[INFO] Temporarily overriding /etc/resolv.conf with Cloudflare DNS (1.1.1.1)"
  cp "$ORIG_RESOLV" "$BACKUP_RESOLV"
  echo "nameserver 1.1.1.1" >"$ORIG_RESOLV"
fi

curl -fsSL https://pkgs.tailscale.com/stable/${ID}/${VER}.noarmor.gpg \
  | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null

echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/${ID} ${VER} main" \
  >/etc/apt/sources.list.d/tailscale.list

apt-get update -qq
apt-get install -y tailscale >/dev/null

if [[ -f /tmp/resolv.conf.backup ]]; then
  echo "[INFO] Restoring original /etc/resolv.conf"
  mv /tmp/resolv.conf.backup /etc/resolv.conf
fi
'

TAGS=$(awk -F': ' '/^tags:/ {print $2}' "$CTID_CONFIG_PATH")
TAGS="${TAGS:+$TAGS; }tailscale"
pct set "$CTID" -tags "$TAGS"

msg_ok "Tailscale installed on CT $CTID"
pct stop "$CTID" >/dev/null
pct start "$CTID" >/dev/null
pct exec "$CTID" -- tailscale up --auth-key="${TAILSCALE_KEY}" >/dev/null 2>&1