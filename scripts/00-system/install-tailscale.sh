#!/usr/bin/env bash
set -euo pipefail

pacman -Sy --noconfirm tailscale
systemctl enable --now tailscaled

tailscale up
