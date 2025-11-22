if [ -z "${SAMBA_WRITER_PASSWORD:-}" ]; then
	SAMBA_WRITER_PASSWORD=$(openssl rand -base64 24)
	export SAMBA_WRITER_PASSWORD
fi

export TAILSCALE_EXIT_NODE="tailscale-exit-node.example.com"

local TAILSCALE_KEY_FILE="~/tailscale-key"
export TAILSCALE_KEY=$(<"$TAILSCALE_KEY_FILE")
