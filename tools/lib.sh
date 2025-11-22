#!/usr/bin/env bash
set -euo pipefail

# Common helpers for the install and container scripts
info()  { printf '%s | INFO  | %s\n' "$(date -Iseconds)" "$*"; }
warn()  { printf '%s | WARN  | %s\n' "$(date -Iseconds)" "$*"; }
die()   { printf '%s | ERROR | %s\n' "$(date -Iseconds)" "$*"; exit 1; }

# Repo layout helpers
# REPO_ROOT is the repository root (scripts/ is expected to be under it)
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS_DIR="${TOOLS_DIR:-$REPO_ROOT/tools}"

install_tailscale_in_ct() {
    local ctid=$1
    "$TOOLS_DIR/tailscale.sh" "$ctid"
}

enable_tailscale_exit_node() {
    local ctid=determine_ctid "$1"
    if [ -z $ctid ]; then
        die "Container $1 not found for enabling Tailscale exit node"
    fi
    
    local exit_node=$TAILSCALE_EXIT_NODE

    info "Attempting to set Tailscale exit node $exit_node for CT $ctid"
    if pct exec "$ctid" -- tailscale set --exit-node="$exit_node" --exit-node-allow-lan-access=true >/dev/null 2>&1; then
        info "Tailscale exit node set for CT $ctid"
    else
        warn "Could not set exit node inside CT (tailscale may need 'up' and auth). Writing marker for manual step."
        pct exec "$ctid" -- bash -c "echo 'Run: tailscale set --exit-node=$exit_node --exit-node-allow-lan-access=true' > /root/.tailscale-set-exit-node"
    fi
}

setup_samba_in_ct() {
    local ctid=$1

    info "Ensuring Samba share is mounted inside CT $ctid"

    pct exec "$ctid" -- bash -c '
        set -euo pipefail
        export DEBIAN_FRONTEND=noninteractive
        if ! dpkg -s cifs-utils >/dev/null 2>&1; then
            apt-get update -qq
            apt-get install -y cifs-utils >/dev/null
        fi
    '

    if [ -z "${SAMBA_WRITER_PASSWORD:-}" ]; then
        warn "SAMBA_WRITER_PASSWORD not set on host; cannot create credentials inside CT"
    else
        pct exec "$ctid" -- bash -c "cat > /root/.smbcredentials <<'EOF'\nusername=smbwriter\npassword=${SAMBA_WRITER_PASSWORD}\nEOF\nchmod 600 /root/.smbcredentials"
    fi

    pct exec "$ctid" -- bash -c "mkdir -p /mnt/storage"

    local hostIp=$(ip addr show vmbr0)
    pct exec "$ctid" -- bash -c "grep -qF '//$hostIp/storage /mnt/storage ' /etc/fstab || echo '//$hostIp/storage /mnt/storage cifs credentials=/root/.smbcredentials,iocharset=utf8,file_mode=0775,dir_mode=0775,vers=3.0 0 0' >> /etc/fstab"

    pct exec "$ctid" -- mount -a
}

create_symlinks_in_ct() {
    local ctid=$1
    shift
    local links=("$@")

    for l in "${links[@]}"; do
        IFS=':' read -r app_path share_subdir <<<"$l"
        local target
        target="/mnt/storage/${share_subdir}"
        info "Creating target and symlink inside CT $ctid: $app_path -> $target"
        pct exec "$ctid" -- bash -c "set -e; mkdir -p \"${target}\"; mkdir -p \"$(dirname \"$app_path\")\"; if [ -L \"${app_path}\" ] || [ -e \"${app_path}\" ]; then rm -rf \"${app_path}\"; fi; ln -s \"${target}\" \"${app_path}\""
    done
}

determine_ctid() {
	ctid=$(pct list | awk -v n="$1" '$3==n { print $1; exit }')
	return $ctid
}

install_app_in_ct() {
    local name=$1        # container name
    local url=$2         # install script URL
    local symlinks=("${!3}")  # array of symlinks (pass as name[@])
    local exit_node="${4:-}"   # optional Tailscale exit node

	local ctid=$(determine_ctid $name)
	if [[ -z $ctid ]]; then
		bash -c "$(curl -fsSL "$url")"
		ctid=$(determine_ctid $name)
	fi

	install_tailscale_in_ct "$ctid" true

	if [ -n "$exit_node" ]; then
		configure_tailscale_exit_node "$ctid"
	fi

	setup_samba_in_ct "$ctid"

	create_symlinks_in_ct "$ctid" "${symlinks[@]}"
		
	echo "$name container setup completed (CT may still require 'tailscale up' inside the CT)."
}