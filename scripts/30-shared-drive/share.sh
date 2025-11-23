#!/usr/bin/env bash
set -euo pipefail

# Load repo helpers if available
TOOLS_LIB="$(cd "$(dirname "$0")/../.." && pwd)/tools/lib.sh"
if [ -f "$TOOLS_LIB" ]; then
    # shellcheck source=/dev/null
    source "$TOOLS_LIB"
fi

STORAGE_DIR="/mnt/storage/media"

info "--- Checking storage directory ---"
if [ ! -d "$STORAGE_DIR" ]; then
    info "Creating $STORAGE_DIR..."
    mkdir -p "$STORAGE_DIR"
else
    info "$STORAGE_DIR exists."
fi

## Create a dedicated homelab user to be the host-side base for unprivileged LXC mappings
# Default UID/GID base used for mapping guest uids/gids -> host uids/gids
HOMELAB_USER=${HOMELAB_USER:-homelab}
HOMELAB_UID=${HOMELAB_UID:-100000}
HOMELAB_GID=${HOMELAB_GID:-${HOMELAB_UID}}

info "Ensuring homelab user '$HOMELAB_USER' exists with UID/GID $HOMELAB_UID/$HOMELAB_GID"

if ! getent group "$HOMELAB_USER" >/dev/null 2>&1; then
    if getent group "$HOMELAB_GID" >/dev/null 2>&1; then
        warn "GID $HOMELAB_GID already exists; creating group without explicit gid"
        groupadd "$HOMELAB_USER"
    else
        groupadd -g "$HOMELAB_GID" "$HOMELAB_USER"
    fi
else
    existing_gid=$(getent group "$HOMELAB_USER" | cut -d: -f3)
    if [ "$existing_gid" != "$HOMELAB_GID" ]; then
        warn "Group $HOMELAB_USER already exists with gid $existing_gid (requested $HOMELAB_GID)"
    fi
fi

if id -u "$HOMELAB_USER" >/dev/null 2>&1; then
    existing_uid=$(id -u "$HOMELAB_USER")
    if [ "$existing_uid" != "$HOMELAB_UID" ]; then
        warn "User $HOMELAB_USER exists with uid $existing_uid (requested $HOMELAB_UID)"
    fi
else
    # create system user without home and without login
    if command -v useradd >/dev/null 2>&1; then
        useradd -M -u "$HOMELAB_UID" -g "$HOMELAB_USER" -s /usr/sbin/nologin "$HOMELAB_USER" 2>/dev/null || \
        useradd -M -u "$HOMELAB_UID" -g "$HOMELAB_USER" -s /bin/false "$HOMELAB_USER"
        info "Created user $HOMELAB_USER with uid $HOMELAB_UID"
    else
        die "useradd not available; please create user $HOMELAB_USER with uid $HOMELAB_UID"
    fi
fi

# Ensure storage dir is owned by homelab
info "Setting ownership of $STORAGE_DIR to $HOMELAB_USER:$HOMELAB_USER"
chown -R "$HOMELAB_USER:$HOMELAB_USER" "$STORAGE_DIR"

# Export these so other scripts (container creators) can use them when registering idmaps
export HOMELAB_USER HOMELAB_UID HOMELAB_GID

info "homelab setup complete. HOMELAB_UID=$HOMELAB_UID HOMELAB_GID=$HOMELAB_GID"

