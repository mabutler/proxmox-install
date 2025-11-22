#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/../../tools/lib.sh"

NAME="qbittorrent"
URL="https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/qbittorrent.sh"

# Optional: set an exit node via environment variable TAILSCALE_EXIT_NODE
EXIT_NODE="${TAILSCALE_EXIT_NODE:-}"

SMB_HOST="127.0.0.1"
SMB_SHARE="storage"
SMB_MOUNTPOINT="/mnt/storage"

# Symlinks inside the container: format app_path:share_subdir
SYMLINKS=(
	"/config:qbittorrent/config"
	"/downloads:qbittorrent/downloads"
	"/watch:qbittorrent/watch"
)

CTID=$(determine_ctid $NAME)
if [[ -e $CTID ]]; then
	bash -c "$(curl -fsSL "$url")"
	CTID=$(determine_ctid $NAME)
fi

setup_generic_container "$NAME" "$URL" \
	--smb-host "$SMB_HOST" --smb-share "$SMB_SHARE" --smb-mountpoint "$SMB_MOUNTPOINT" \
	--symlink "${SYMLINKS[0]}" --symlink "${SYMLINKS[1]}" --symlink "${SYMLINKS[2]}" \
	--exit-node "$EXIT_NODE"

echo "qBittorrent container setup completed (CT may still require 'tailscale up' inside the CT)."

