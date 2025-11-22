#!/usr/bin/env bash
set -euo pipefail

# Common helpers for the install and container scripts
info()  { printf '%s | INFO  | %s\n' "$(date -Iseconds)" "$*"; }
warn()  { printf '%s | WARN  | %s\n' "$(date -Iseconds)" "$*"; }
die()   { printf '%s | ERROR | %s\n' "$(date -Iseconds)" "$*"; exit 1; }

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        die "This script must be run as root"
    fi
}

ensure_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        die "Required command '$1' not found"
    fi
}

# Repo layout helpers
# REPO_ROOT is the repository root (scripts/ is expected to be under it)
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS_DIR="${TOOLS_DIR:-$REPO_ROOT/tools}"

# Fail fast if Proxmox LXC tooling isn't available where we expect it to be.
ensure_command pct

get_ctid_by_name() {
    local name=$1
    pct list 2>/dev/null | awk -v n="$name" '$0 ~ (" " n "($| )") {print $1; exit}' || true
}

container_exists() {
    local name=$1
    if pct list 2>/dev/null | awk -v n="$name" '$0 ~ (" " n "($| )") {exit 0} END{exit 1}'; then
        return 0
    fi
    return 1
}

next_mp_index() {
    local ctid=$1
    local conf="/etc/pve/lxc/${ctid}.conf"
    for i in 0 1 2 3 4 5 6 7 8 9; do
        if ! grep -q "^mp${i}:" "$conf" 2>/dev/null; then
            printf '%s' "$i"
            return 0
        fi
    done
    die "No free mp index available for container $ctid"
}

ensure_mount() {
    local ctid=$1
    local host_path=$2
    local ct_path=$3
    local opts=${4:-}
    local conf="/etc/pve/lxc/${ctid}.conf"

    if grep -qE "mp=[^,]*${ct_path}($|,)" "$conf" 2>/dev/null; then
        info "Mount for $ct_path already exists in CT $ctid"
        return 0
    fi

    if [ ! -e "$host_path" ]; then
        warn "Host path $host_path does not exist; creating"
        mkdir -p "$host_path"
    fi

    local idx
    idx=$(next_mp_index "$ctid")
    info "Adding mount mp$idx: $host_path -> $ct_path"
    if [ -n "$opts" ]; then
        pct set "$ctid" -mp${idx} "$host_path,mp=${ct_path},${opts}"
    else
        pct set "$ctid" -mp${idx} "$host_path,mp=${ct_path}"
    fi
}

apply_mounts() {
    local ctid=$1
    shift || true
    local mounts=("$@")
    for m in "${mounts[@]}"; do
        IFS=':' read -r host ct opts <<<"$m"
        ensure_mount "$ctid" "$host" "$ct" "$opts"
    done
}

install_tailscale_in_ct() {
    local ctid=$1
    if [ -x "$TOOLS_DIR/tailscale.sh" ]; then
        "$TOOLS_DIR/tailscale.sh" "$ctid"
    else
        warn "Tailscale helper not found at $TOOLS_DIR/tailscale.sh"
    fi
}

configure_tailscale_exit_node() {
    local ctid=$1
    local exit_node=$2
    if [ -z "$exit_node" ]; then
        return 0
    fi
    info "Attempting to set Tailscale exit node $exit_node for CT $ctid"
    if pct exec "$ctid" -- tailscale set --exit-node="$exit_node" --exit-node-allow-lan-access=true >/dev/null 2>&1; then
        info "Tailscale exit node set for CT $ctid"
    else
        warn "Could not set exit node inside CT (tailscale may need 'up' and auth). Writing marker for manual step."
        pct exec "$ctid" -- bash -c "echo 'Run: tailscale set --exit-node=$exit_node --exit-node-allow-lan-access=true' > /root/.tailscale-set-exit-node"
    fi
}

ensure_samba_mounted_in_ct() {
    local ctid=$1
    local smb_host=$2
    local smb_share=$3
    local mountpoint=$4

    info "Ensuring Samba share //$smb_host/$smb_share is mounted at $mountpoint inside CT $ctid"

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

    pct exec "$ctid" -- bash -c "mkdir -p ${mountpoint}"

    pct exec "$ctid" -- bash -c "grep -qF '//$smb_host/$smb_share ${mountpoint} ' /etc/fstab || echo '//$smb_host/$smb_share ${mountpoint} cifs credentials=/root/.smbcredentials,iocharset=utf8,file_mode=0775,dir_mode=0775,vers=3.0 0 0' >> /etc/fstab"

    pct exec "$ctid" -- bash -c "mountpoint -q ${mountpoint} || mount ${mountpoint} || true"
}

create_symlinks_in_ct() {
    local ctid=$1
    local smb_root=$2
    shift 2 || true
    local links=("$@")

    for l in "${links[@]}"; do
        IFS=':' read -r app_path share_subdir <<<"$l"
        local target
        target="${smb_root%/}/${share_subdir}"
        info "Creating target and symlink inside CT $ctid: $app_path -> $target"
        pct exec "$ctid" -- bash -c "set -e; mkdir -p \"${target}\"; mkdir -p \"$(dirname \"$app_path\")\"; if [ -L \"${app_path}\" ] || [ -e \"${app_path}\" ]; then rm -rf \"${app_path}\"; fi; ln -s \"${target}\" \"${app_path}\""
    done
}

setup_generic_container() {
    local name=$1
    local url=${2:-}
    shift 2 || true
    local mounts=()
    local exit_node=
    local smb_host=""
    local smb_share="storage"
    local smb_mountpoint="/mnt/storage"
    local symlinks=()

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --mount)
                mounts+=("$2"); shift 2;;
            --exit-node)
                exit_node="$2"; shift 2;;
            --smb-host)
                smb_host="$2"; shift 2;;
            --smb-share)
                smb_share="$2"; shift 2;;
            --smb-mountpoint)
                smb_mountpoint="$2"; shift 2;;
            --symlink)
                symlinks+=("$2"); shift 2;;
            *) shift;;
        esac
    done

    local ctid
    if [ -n "$url" ]; then
        ctid=$(ensure_container_from_url "$name" "$url")
    else
        if container_exists "$name"; then
            ctid=$(pct list 2>/dev/null | awk -v n="$name" '$3==n {print $1; exit}')
        else
            die "No creation URL provided for container $name"
        fi
    fi

    info "Configuring container $name (CTID $ctid)"

    if [ ${#mounts[@]} -gt 0 ]; then
        apply_mounts "$ctid" "${mounts[@]}"
    fi

    if [ -n "$smb_host" ]; then
        ensure_samba_mounted_in_ct "$ctid" "$smb_host" "$smb_share" "$smb_mountpoint"
        if [ ${#symlinks[@]} -gt 0 ]; then
            create_symlinks_in_ct "$ctid" "$smb_mountpoint" "${symlinks[@]}"
        fi
    fi

    install_tailscale_in_ct "$ctid"

    if [ -n "$exit_node" ]; then
        configure_tailscale_exit_node "$ctid" "$exit_node"
    fi

    info "Container $name configured"
}
ensure_container_from_url() {
    local name=$1
    local url=$2
    if container_exists "$name"; then
        info "LXC $name already exists"
    else
        info "Creating LXC $name from $url"
        # Execute the remote creation script directly via command substitution
        # using the form requested by the user. This will spawn a new bash
        # process which executes the fetched script content.
        if command -v curl >/dev/null 2>&1; then
            bash -c "$(curl -fsSL "$url")" || die "Failed to run creation script from $url"
        elif command -v wget >/dev/null 2>&1; then
            bash -c "$(wget -qO- "$url")" || die "Failed to run creation script from $url"
        else
            die "curl or wget required to fetch $url"
        fi
    fi

    # return CTID on stdout (use tolerant lookup)
    get_ctid_by_name "$name"
}
