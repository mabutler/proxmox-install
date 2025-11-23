#!/usr/bin/env bash
set -euo pipefail

if ! dpkg -s tailscale >/dev/null 2>&1; then
	info "Installing Tailscale"
	curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg -o /usr/share/keyrings/tailscale-archive-keyring.gpg
	curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list -o /etc/apt/sources.list.d/tailscale.list

	apt-get update -qq
	apt-get install -y tailscale

	if ! tailscale up --auth-key=$(cat /root/tailscale-key); then
		warn "tailscale up failed or requires interactive auth"
	fi
else
	info "tailscale is already installed"
fi
