#!/usr/bin/env bash
set -euo pipefail

# Load helpers
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/../lib.sh"

require_root

# Optional behavior controls
TAILSCALE_AUTO_UP="${TAILSCALE_AUTO_UP:-false}"
TAILSCALE_EXIT_NODE="${TAILSCALE_EXIT_NODE:-}"

if ! dpkg -s tailscale >/dev/null 2>&1; then
	info "Installing Tailscale"
	curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg -o /usr/share/keyrings/tailscale-archive-keyring.gpg
	curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list -o /etc/apt/sources.list.d/tailscale.list

	apt-get update -qq
	apt-get install -y tailscale

	if [ "$TAILSCALE_AUTO_UP" = "true" ]; then
		if ! tailscale up; then
			warn "tailscale up failed or requires interactive auth"
		fi
	else
		info "Tailscale installed. Set TAILSCALE_AUTO_UP=true to run 'tailscale up' automatically."
	fi
else
	info "tailscale is already installed"
fi
