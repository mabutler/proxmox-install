#!/usr/bin/env bash
set -euo pipefail

if ! dpkg -s tailscale >/dev/null 2>&1; then
	curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg > /usr/share/keyrings/tailscale-archive-keyring.gpg
	curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list > /etc/apt/sources.list.d/tailscale.list

	apt-get update -qq
	apt-get install -y tailscale

	tailscale up
else
	echo "tailscale is already installed"
fi

tailscale set --exit-node=ro-buh-wg-001.mullvad.ts.net --exit-node-allow-lan-access=true
