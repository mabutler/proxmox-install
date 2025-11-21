#!/usr/bin/env bash
set -euo pipefail

STORAGE_DIR="/mnt/storage/media"
SMB_USER="smbwriter"
SMB_CONF="/etc/samba/smb.conf"

echo "--- Checking storage directory ---"
if [ ! -d "$STORAGE_DIR" ]; then
    echo "Creating $STORAGE_DIR..."
    mkdir -p "$STORAGE_DIR"
    chmod 755 "$STORAGE_DIR"
else
    echo "$STORAGE_DIR exists."
fi


echo "--- Checking Linux user '$SMB_USER' ---"
if ! id "$SMB_USER" >/dev/null 2>&1; then
    echo "Creating user $SMB_USER..."
    useradd -M -s /usr/sbin/nologin "$SMB_USER"
else
    echo "User $SMB_USER exists."
fi

# Ensure ownership
CURRENT_OWNER=$(stat -c "%U" "$STORAGE_DIR")
if [ "$CURRENT_OWNER" != "$SMB_USER" ]; then
    echo "Fixing directory ownership..."
    chown "$SMB_USER:$SMB_USER" "$STORAGE_DIR"
fi


echo "Setting Samba user password..."
(echo "$SAMBA_WRITER_PASSWORD"; echo "$SAMBA_WRITER_PASSWORD") | smbpasswd -a "$SMB_USER"


echo "--- Checking Samba configuration ---"
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
    echo "Writing Samba configuration..."
    echo "$EXPECTED_CONF_CONTENT" > "$SMB_CONF"
else
    echo "Samba configuration is already correct."
fi


echo "--- Restarting Samba ---"
systemctl restart smbd
systemctl restart nmbd
echo "Setup complete."
