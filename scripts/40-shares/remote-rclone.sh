#!/bin/bash
set -euo pipefail

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
   echo "This script must be run as root"
   exit 1
fi

USERNAME="loki"
USER_HOME="/home/$USERNAME"

# Configuration - EDIT THESE VALUES
# Prompt for server connection details
read -p "Enter server hostname or IP: " SERVER_HOST
read -p "Enter SSH username: " SERVER_USER
read -p "Enter SSH port [22]: " SERVER_PORT
SERVER_PORT=${SERVER_PORT:-22}  # Default to 22 if empty
REMOTE_DOWNLOADS_PATH="downloads/qbittorrent/completed"
REMOTE_TORRENTS_PATH="/path/to/server/torrents"
LOCAL_MEDIA_PATH="/mnt/storage/media"
LOCAL_TORRENTS_PATH="/mnt/storage/torrents"
BANDWIDTH_LIMIT="500K"  # Adjust based on your connection
SYNC_INTERVAL_MEDIA="*/30 * * * *"  # Every 30 minutes
SYNC_INTERVAL_TORRENTS="*/5 * * * *"  # Every 5 minutes

echo "=== rclone Media Sync Setup (as user: $USERNAME) ==="
echo

# Verify loki user exists
if ! id "$USERNAME" &>/dev/null; then
    echo "Error: User '$USERNAME' does not exist."
    exit 1
fi

echo "Creating and setting up local directories..."
mkdir -p "$LOCAL_MEDIA_PATH"
mkdir -p "$LOCAL_TORRENTS_PATH"

# Set ownership to loki user
chown -R "$USERNAME:$USERNAME" "$LOCAL_MEDIA_PATH"
chown -R "$USERNAME:$USERNAME" "$LOCAL_TORRENTS_PATH"

# ============================================
# LOKI USER OPERATIONS
# ============================================

echo "Switching to user '$USERNAME' for remaining setup..."
echo

# Create a script that will run as loki user
SETUP_SCRIPT=$(mktemp)
chmod o+rx "$SETUP_SCRIPT"

cat > "$SETUP_SCRIPT" << 'LOKI_SCRIPT_END'
#!/bin/bash
set -e

USERNAME="loki"
USER_HOME="/home/$USERNAME"
SERVER_HOST="__SERVER_HOST__"
SERVER_USER="__SERVER_USER__"
SERVER_PORT="__SERVER_PORT__"
REMOTE_DOWNLOADS_PATH="__REMOTE_DOWNLOADS_PATH__"
REMOTE_TORRENTS_PATH="__REMOTE_TORRENTS_PATH__"
LOCAL_MEDIA_PATH="__LOCAL_MEDIA_PATH__"
LOCAL_TORRENTS_PATH="__LOCAL_TORRENTS_PATH__"
BANDWIDTH_LIMIT="__BANDWIDTH_LIMIT__"
SYNC_INTERVAL_MEDIA="__SYNC_INTERVAL_MEDIA__"
SYNC_INTERVAL_TORRENTS="__SYNC_INTERVAL_TORRENTS__"

echo "Setting up SSH key for $USERNAME..."
SSH_KEY="$USER_HOME/.ssh/id_rsa"
SSH_PUB_KEY="$SSH_KEY.pub"

if [ -f "$SSH_KEY" ]; then
    echo "✓ SSH key already exists at $SSH_KEY"
else
    echo "Creating SSH key..."
    ssh-keygen -t rsa -b 4096 -f "$SSH_KEY" -N "" -C "rclone-sync-$USERNAME-$(hostname)"
    chmod 600 "$SSH_KEY"
    chmod 644 "$SSH_PUB_KEY"
    echo "✓ SSH key created at $SSH_KEY"
fi
echo

ssh-copy-id -i $SSH_PUB_KEY -p $SERVER_PORT $SERVER_USER@$SERVER_HOST

# Test SSH connection
echo
echo "Testing SSH connection..."
if ssh -p "$SERVER_PORT" -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SERVER_USER@$SERVER_HOST" exit 2>/dev/null; then
    echo "✓ SSH key authentication working!"
else
    echo "⚠ SSH connection test failed."
    echo "The setup will continue, but you may need to fix the SSH connection manually."
    echo "Test with: ssh -p $SERVER_PORT -i $SSH_KEY $SERVER_USER@$SERVER_HOST"
fi
echo

echo "Configuring rclone remote connection..."

# Check if remote already exists
if rclone listremotes 2>/dev/null | grep -q "^mediaserver:$"; then
    echo "Remote 'mediaserver' already exists. Removing old configuration..."
    rclone config delete mediaserver 2>/dev/null || true
fi

echo "Setting up 'mediaserver' remote with SSH key authentication..."

# Create rclone config
rclone config create mediaserver sftp \
    host "$SERVER_HOST" \
    user "$SERVER_USER" \
    port "$SERVER_PORT" \
    key_file "$SSH_KEY" \
    use_insecure_cipher false \
    disable_hashcheck false

echo "Testing rclone connection..."
if rclone lsf mediaserver: --max-depth 1 2>/dev/null; then
    echo "✓ rclone connection successful!"
else
    echo "⚠ rclone connection test failed. You may need to fix this manually."
fi
echo

echo "Creating sync scripts..."
SCRIPT_DIR="$USER_HOME/.local/bin"

# Media sync script
cat > "$SCRIPT_DIR/sync-media.sh" << 'MEDIA_SYNC_SCRIPT'
#!/bin/bash
# Media sync script - pulls media from server

LOG_FILE="$HOME/.local/log/rclone-media.log"
mkdir -p "$(dirname "$LOG_FILE")"

echo "[$(date)] Starting media sync..." >> "$LOG_FILE"

echo "[$(date)] Syncing $category..." >> "$LOG_FILE"
rclone sync "mediaserver:REMOTE_DOWNLOADS_PATH/" "LOCAL_MEDIA_PATH/" \
    --bwlimit BANDWIDTH_LIMIT \
    --transfers 1 \
    --retries 10 \
    --low-level-retries 20 \
    --contimeout 60s \
    --timeout 300s \
    --log-level INFO \
    --log-file "$LOG_FILE" \
    2>&1 | tee -a "$LOG_FILE"

echo "[$(date)] Media sync completed" >> "$LOG_FILE"
MEDIA_SYNC_SCRIPT

# Torrent sync script (push torrents to server)
cat > "$SCRIPT_DIR/sync-torrents.sh" << 'TORRENT_SYNC_SCRIPT'
#!/bin/bash
# Torrent sync script - pushes .torrent files to server

LOG_FILE="$HOME/.local/log/rclone-torrents.log"
mkdir -p "$(dirname "$LOG_FILE")"

echo "[$(date)] Starting torrent sync..." >> "$LOG_FILE"

rclone copy "LOCAL_TORRENTS_PATH" "mediaserver:REMOTE_TORRENTS_PATH" \
    --include "*.torrent" \
    --transfers 2 \
    --retries 5 \
    --log-level INFO \
    --log-file "$LOG_FILE" \
    2>&1 | tee -a "$LOG_FILE"

echo "[$(date)] Torrent sync completed" >> "$LOG_FILE"
TORRENT_SYNC_SCRIPT

# Replace placeholders
sed -i "s|REMOTE_DOWNLOADS_PATH|$REMOTE_DOWNLOADS_PATH|g" "$SCRIPT_DIR/sync-media.sh"
sed -i "s|LOCAL_MEDIA_PATH|$LOCAL_MEDIA_PATH|g" "$SCRIPT_DIR/sync-media.sh"
sed -i "s|BANDWIDTH_LIMIT|$BANDWIDTH_LIMIT|g" "$SCRIPT_DIR/sync-media.sh"
sed -i "s|REMOTE_TORRENTS_PATH|$REMOTE_TORRENTS_PATH|g" "$SCRIPT_DIR/sync-torrents.sh"
sed -i "s|LOCAL_TORRENTS_PATH|$LOCAL_TORRENTS_PATH|g" "$SCRIPT_DIR/sync-torrents.sh"

chmod +x "$SCRIPT_DIR/sync-media.sh"
chmod +x "$SCRIPT_DIR/sync-torrents.sh"

echo "✓ Sync scripts created:"
echo "  - $SCRIPT_DIR/sync-media.sh"
echo "  - $SCRIPT_DIR/sync-torrents.sh"
echo

echo "Setting up cron jobs..."
# Create temporary crontab file
TEMP_CRON=$(mktemp)
crontab -l 2>/dev/null > "$TEMP_CRON" || true

# Remove existing entries if they exist
sed -i '/sync-media.sh/d' "$TEMP_CRON"
sed -i '/sync-torrents.sh/d' "$TEMP_CRON"

# Add new cron jobs
echo "# rclone media sync - pull downloads from server" >> "$TEMP_CRON"
echo "$SYNC_INTERVAL_MEDIA $SCRIPT_DIR/sync-media.sh" >> "$TEMP_CRON"
echo "" >> "$TEMP_CRON"
echo "# rclone torrent sync - push torrents to server" >> "$TEMP_CRON"
echo "$SYNC_INTERVAL_TORRENTS $SCRIPT_DIR/sync-torrents.sh" >> "$TEMP_CRON"

# Install new crontab
crontab "$TEMP_CRON"
rm "$TEMP_CRON"

echo "✓ Cron jobs installed for user $USERNAME:"
echo "  - Media sync: $SYNC_INTERVAL_MEDIA"
echo "  - Torrent sync: $SYNC_INTERVAL_TORRENTS"
echo

LOKI_SCRIPT_END

# Replace placeholders in the loki script
sed -i "s|__SERVER_HOST__|$SERVER_HOST|g" "$SETUP_SCRIPT"
sed -i "s|__SERVER_USER__|$SERVER_USER|g" "$SETUP_SCRIPT"
sed -i "s|__SERVER_PORT__|$SERVER_PORT|g" "$SETUP_SCRIPT"
sed -i "s|__REMOTE_DOWNLOADS_PATH__|$REMOTE_DOWNLOADS_PATH|g" "$SETUP_SCRIPT"
sed -i "s|__REMOTE_TORRENTS_PATH__|$REMOTE_TORRENTS_PATH|g" "$SETUP_SCRIPT"
sed -i "s|__LOCAL_MEDIA_PATH__|$LOCAL_MEDIA_PATH|g" "$SETUP_SCRIPT"
sed -i "s|__LOCAL_TORRENTS_PATH__|$LOCAL_TORRENTS_PATH|g" "$SETUP_SCRIPT"
sed -i "s|__BANDWIDTH_LIMIT__|$BANDWIDTH_LIMIT|g" "$SETUP_SCRIPT"
sed -i "s|__SYNC_INTERVAL_MEDIA__|$SYNC_INTERVAL_MEDIA|g" "$SETUP_SCRIPT"
sed -i "s|__SYNC_INTERVAL_TORRENTS__|$SYNC_INTERVAL_TORRENTS|g" "$SETUP_SCRIPT"

chmod +x "$SETUP_SCRIPT"

# Run the script as loki user
sudo -u "$USERNAME" bash "$SETUP_SCRIPT"

# Clean up
rm "$SETUP_SCRIPT"

echo "The rclone media sync setup is complete."