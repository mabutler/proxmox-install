#!/usr/bin/env bash
set -euo pipefail

PACKAGES=(vim tmux git cronie inxi  openssl rclone less tailscale)
#mergerfs snapraid
pacman -Sy --noconfirm "${PACKAGES[@]}"
