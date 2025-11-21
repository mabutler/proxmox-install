#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

PACKAGES="vim tmux git mergerfs inxi snapraid samba openssl"

for pkg in $PACKAGES; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        apt-get update -qq
        apt-get install -y "$pkg"
    else
        echo "$pkg is already installed"
    fi
done
