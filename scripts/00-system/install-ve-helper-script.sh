#!/usr/bin/env bash
set -euo pipefail

# Run post-pve-install script from community-scripts (wget or curl)
URL="https://github.com/community-scripts/ProxmoxVE/raw/main/tools/pve/post-pve-install.sh"
if command -v curl >/dev/null 2>&1; then
	curl -fsSL "$URL" | bash -s --
elif command -v wget >/dev/null 2>&1; then
	wget -qO- "$URL" | bash -s --
else
	echo "curl or wget required to fetch $URL"
	exit 1
fi
