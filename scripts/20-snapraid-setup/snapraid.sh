#!/usr/bin/env bash
set -euo pipefail

# ------------------------------
# 1. Variables
# ------------------------------
PARITY_MP="/mnt/parity1"
DATA_MPS=("/mnt/disk1" "/mnt/disk2" "/mnt/disk3")
SNAPRAID_CONF="/etc/snapraid.conf"

# Directories for SnapRAID parity and content files
PARITY_DIR="$PARITY_MP/snapraid.parity"
CONTENT_DIRS=()
for mp in "${DATA_MPS[@]}"; do
    CONTENT_DIRS+=("$mp/snapraid.content")
done

# ------------------------------
# 3. Create directories
# ------------------------------
mkdir -p "$PARITY_DIR"
for dir in "${CONTENT_DIRS[@]}"; do
    mkdir -p "$dir"
done

# ------------------------------
# 4. Write SnapRAID configuration
# ------------------------------
cat > "$SNAPRAID_CONF" <<EOL
# Parity drive
parity $PARITY_DIR

# Data drives
EOL

for dir in "${CONTENT_DIRS[@]}"; do
    echo "content $dir" >> "$SNAPRAID_CONF"
done

# Exclusions
cat >> "$SNAPRAID_CONF" <<EOL

# Exclude patterns
exclude *.unrecoverable
exclude /tmp/
exclude /lost+found/
exclude downloads/
exclude appdata/
exclude *.!sync

# Optional settings
block_size 256
auto_fix_parity true
EOL

echo "SnapRAID configuration written to $SNAPRAID_CONF"

# ------------------------------
# 5. Add cron jobs
# ------------------------------
CRON_JOB_SYNC="0 2 * * * /usr/bin/snapraid -c $SNAPRAID_CONF sync >> /var/log/snapraid-sync.log 2>&1"
CRON_JOB_SCRUB="0 3 * * 0 /usr/bin/snapraid -c $SNAPRAID_CONF scrub >> /var/log/snapraid-scrub.log 2>&1"

EXISTING_CRON=$(crontab -l 2>/dev/null || true)

# Add jobs if missing
{
	echo "$EXISTING_CRON" |
	grep -v "/usr/bin/snapraid -c"
	echo "$CRON_JOB_SYNC"
	echo "$CRON_JOB_SCRUB"
} | crontab -

echo "SnapRAID cron jobs added (daily sync at 2am, weekly scrub at 3am Sunday)"
