if [ -z "${SAMBA_WRITER_PASSWORD:-}" ]; then
	SAMBA_WRITER_PASSWORD=$(openssl rand -base64 24)
	export SAMBA_WRITER_PASSWORD
fi

export TAILSCALE_EXIT_NODE="tailscale-exit-node.example.com"

export TAILSCALE_CONFIG_FILE="~/tailscale-key"
