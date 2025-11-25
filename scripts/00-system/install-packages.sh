#!/usr/bin/env bash
set -euo pipefail


sudo pacman -Syu --noconfirm --needed

PACKAGES=(vim tmux git cronie openssl rclone less tailscale)
pacman -S --needed --noconfirm "${PACKAGES[@]}"
pacman -S --needed --noconfirm base-devel git

if ! command -v paru &> /dev/null; then
    echo "Installing paru..."
    
    git clone https://aur.archlinux.org/paru.git /tmp/paru
    cd /tmp/paru
    makepkg -si --noconfirm
    cd -
    rm -rf /tmp/paru
fi

paru -S --noconfirm --needed mergerfs snapraid
