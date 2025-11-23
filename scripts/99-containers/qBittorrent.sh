#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/../../tools/lib.sh"

NAME="qbittorrent"
URL="https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/qbittorrent.sh"

# Symlinks inside the container: format app_path:share_subdir
MOUNTS=(
	"config:qbittorrent/config"
	"downloads:qbittorrent/downloads"
	"watch:qbittorrent/watch"
)

UIDS=(
	100
)

install_app_in_ct "qbittorrent" "$URL" MOUNTS[@] UIDS[@]
enable_tailscale_exit_node "qbittorrent"
