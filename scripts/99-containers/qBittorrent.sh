NAME="qbittorrent"
if pct list | awk '$3=="'"$NAME"'" {exit 0} END{exit 1}'; then
	echo "LXE $NAME already exists"
else
	bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/qbittorrent.sh)"
fi

CTID="$(pct list | awk '$3=="'"$NAME"'" {print $1}')"
"$TOOLS_DIR/tailscale.sh" "$CTID"

