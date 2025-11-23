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
    local ctid=$(determine_ctid "$1")
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

        echo "mp${mp_index}: $host_path,mp=${container_path},backup=0" >> "/etc/pve/lxc/${ctid}.conf"
        info "Creating mount inside CT $ctid: $container_path -> $host_path"
        mp_index=$((mp_index + 1))
    done
}

# Register lxc idmap lines for a container config
# Usage: register_idmaps_for_ct <ctid> "lxc.idmap = u 0 100000 65536" "lxc.idmap = g 0 100000 65536"
register_idmaps_for_ct() {
    local ctid=$1
    shift
    local conf="/etc/pve/lxc/${ctid}.conf"
    local host_uid_base=$(id -u "homelab")
    local host_gid_base=$(getent group "homelab" | cut -d: -f3)

    MAP_UIDS=("$@")\

    if [ -z "$ctid" ]; then
        die "register_idmaps_for_ct requires a ctid"
    fi

    if [ ! -f "$conf" ]; then
        die "Container config $conf not found"
    fi

    # Remove any existing lxc.idmap lines to avoid duplicates
    awk '!/^lxc.idmap\s*=/' "$conf" > "${conf}.tmp" && mv "${conf}.tmp" "$conf"

    for idline in "$@"; do
        echo "$idline" >> "$conf"
        info "Wrote idmap to $conf: $idline"
    done

    # Container UID space for unprivileged LXC
    CT_MIN=0
    CT_MAX=65535

    # Sort and deduplicate the UIDs that need special mapping
    mapfile -t MAP_UIDS < <(printf "%s\n" "${MAP_UIDS[@]}" | sort -n | uniq)

    echo "# --- BEGIN GENERATED UID/GID MAPPINGS ---"
    echo "# Mapping CT UIDs → host UID ${host_uid_base}"
    echo "# Split-range mapping covering entire 0–65535 space"

    prev_end=$CT_MIN

    for uid in "${MAP_UIDS[@]}"; do
        if (( uid < CT_MIN || uid > CT_MAX )); then
            echo "Error: UID ${uid} out of allowed container range 0–65535" >&2
            exit 1
        fi

        # Range before this UID
        if (( uid > prev_end )); then
            range_len=$((uid - prev_end))
            echo "lxc.idmap = u ${prev_end} $((100000 + prev_end)) ${range_len}" >> "$conf"
            echo "lxc.idmap = g ${prev_end} $((100000 + prev_end)) ${range_len}" >> "$conf"
        fi

        # The special mapped user
        echo "lxc.idmap = u ${uid} ${host_uid_base} 1" >> "$conf"
        echo "lxc.idmap = g ${uid} ${host_uid_base} 1" >> "$conf"

        prev_end=$((uid + 1))
    done

    # Trailing range after last mapped UID
    if (( prev_end <= CT_MAX )); then
        range_len=$((CT_MAX - prev_end + 1))
        echo "lxc.idmap = u ${prev_end} $((100000 + prev_end)) ${range_len}" >> "$conf"
        echo "lxc.idmap = g ${prev_end} $((100000 + prev_end)) ${range_len}" >> "$conf"
    fi
}

determine_ctid() {
	pct list | awk -v n="$1" '$3==n { print $1; exit }'
}

install_app_in_ct() {
    local name=$1        # container name
    local url=$2         # install script URL
    local symlinks=("${!3}")  # array of symlinks (pass as name[@])
    local uid_maps=("${!4}")   # optional array of uid maps (pass as name[@])

	local ctid=$(determine_ctid $name)
	if [[ -z $ctid ]]; then
		bash -c "$(curl -fsSL "$url")"
		ctid=$(determine_ctid $name)
	fi

	create_mounts_in_ct "$ctid" "${symlinks[@]}"

    if [ "${#uid_maps[@]}" -gt 0 ]; then
        register_idmaps_for_ct "$ctid" "${uid_maps[@]}"
    fi

	install_tailscale_in_ct "$ctid"

	echo "$name container setup completed (CT may still require 'tailscale up' inside the CT)."
}
