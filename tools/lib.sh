#!/usr/bin/env bash
set -euo pipefail

# Common helpers for the install and container scripts
info()  { printf '%s | INFO  | %s\n' "$(date -Iseconds)" "$*"; }
warn()  { printf '%s | WARN  | %s\n' "$(date -Iseconds)" "$*"; }
die()   { printf '%s | ERROR | %s\n' "$(date -Iseconds)" "$*"; exit 1; }

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

create_mounts_in_ct() {
    local ctid=$1
    shift
    local mounts=("$@")

    local mp_index=0
    for l in "${mounts[@]}"; do
        IFS=':' read -r container_path host_subdir <<<"$l"
        local host_path="/mnt/storage/${host_subdir}"

        mkdir -p "$host_path"

        echo "mp${mp_index}: $host_path,mp=${container_path},backup=0,shift=1" >> "/etc/pve/lxc/${ctid}.conf"
        info "Creating mount inside CT $ctid: $container_path -> $host_path"
        mp_index=$((mp_index + 1))
    done
}

determine_ctid() {
	pct list | awk -v n="$1" '$3==n { print $1; exit }'
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

	create_mounts_in_ct "$ctid" "${symlinks[@]}"
		
	echo "$name container setup completed (CT may still require 'tailscale up' inside the CT)."
}
