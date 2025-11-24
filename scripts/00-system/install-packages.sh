#!/usr/bin/env bash
set -euo pipefail

PACKAGES=(vim tmux git mergerfs inxi snapraid openssl rclone less tailscale)

pacman -Sy --noconfirm "${PACKAGES[@]}"
