#!/usr/bin/env bash
set -euo pipefail

# Run post-pve-install script from community-scripts (wget or curl)
URL="https://github.com/community-scripts/ProxmoxVE/raw/main/tools/pve/post-pve-install.sh"
tmp=$(mktemp) || { echo "Could not create temp file"; exit 1; }
if command -v curl >/dev/null 2>&1; then
	curl -fsSL "$URL" -o "$tmp" || { rm -f "$tmp"; echo "Failed to fetch $URL"; exit 1; }
elif command -v wget >/dev/null 2>&1; then
	wget -qO "$tmp" "$URL" || { rm -f "$tmp"; echo "Failed to fetch $URL"; exit 1; }
else
	rm -f "$tmp"
	echo "curl or wget required to fetch $URL"
	exit 1
fi

if command -v script >/dev/null 2>&1; then
	script -q -c "bash \"$tmp\"" /dev/null || { rm -f "$tmp"; echo "Failed to run $URL"; exit 1; }
else
	echo "'script' not available — running without pty; script may fail if it requires a TTY"
	bash "$tmp" || { rm -f "$tmp"; echo "Failed to run $URL"; exit 1; }
fi

rm -f "$tmp"
