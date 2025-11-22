#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/../../tools/lib.sh"

NAME="qbittorrent"
URL="https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/qbittorrent.sh"

# Symlinks inside the container: format app_path:share_subdir
SYMLINKS=(
	"config:qbittorrent/config"
	"downloads:qbittorrent/downloads"
	"watch:qbittorrent/watch"
)

install_app_in_ct "qbittorrent" "$URL" SYMLINKS[@]
enable_tailscale_exit_node "qbittorrent"
