#!/usr/bin/env bash
set -euo pipefail

# Load repo helpers if available
LIB_FILE="$(cd "$(dirname "$0")/../.." && pwd)/scripts/lib.sh"
if [ -f "$LIB_FILE" ]; then
    # shellcheck source=/dev/null
    source "$LIB_FILE"
fi

STORAGE_DIR="/mnt/storage/media"
SMB_USER="smbwriter"
SMB_CONF="/etc/samba/smb.conf"

info "--- Checking storage directory ---"
if [ ! -d "$STORAGE_DIR" ]; then
    info "Creating $STORAGE_DIR..."
    mkdir -p "$STORAGE_DIR"
    chmod 755 "$STORAGE_DIR"
else
    info "$STORAGE_DIR exists."
fi

info "--- Checking Linux user '$SMB_USER' ---"
if ! id "$SMB_USER" >/dev/null 2>&1; then
    info "Creating user $SMB_USER..."
    useradd -M -s /usr/sbin/nologin "$SMB_USER"
else
    info "User $SMB_USER exists."
fi

# Ensure ownership
CURRENT_OWNER=$(stat -c "%U" "$STORAGE_DIR")
if [ "$CURRENT_OWNER" != "$SMB_USER" ]; then
    info "Fixing directory ownership..."
    chown "$SMB_USER:$SMB_USER" "$STORAGE_DIR"
fi

info "Setting Samba user password..."
if [ -z "${SAMBA_WRITER_PASSWORD:-}" ]; then
    warn "SAMBA_WRITER_PASSWORD not set; make sure to source tools/secrets.sh before running this script"
fi
(echo "$SAMBA_WRITER_PASSWORD"; echo "$SAMBA_WRITER_PASSWORD") | smbpasswd -a "$SMB_USER"

info "--- Checking Samba configuration ---"
EXPECTED_CONF_CONTENT=$(cat <<EOF
[global]
   workgroup = WORKGROUP
   server string = Storage Server
   security = user
   map to guest = Bad User
   guest account = nobody
   unix extensions = no

[storage]
   path = $STORAGE_DIR
   browseable = yes
   guest ok = yes
   read only = yes
   writeable = yes
   valid users = smbwriter
   force user = smbwriter
EOF
)

# Compare existing config
if [ ! -f "$SMB_CONF" ] || ! diff -q <(echo "$EXPECTED_CONF_CONTENT") "$SMB_CONF" >/dev/null 2>&1; then
    info "Writing Samba configuration..."
    echo "$EXPECTED_CONF_CONTENT" > "$SMB_CONF"
else
    info "Samba configuration is already correct."
fi

info "--- Restarting Samba ---"
systemctl restart smbd
systemctl restart nmbd
info "Setup complete."
