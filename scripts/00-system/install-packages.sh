#!/usr/bin/env bash
set -euo pipefail

# Load helpers
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/../../tools/lib.sh"

export DEBIAN_FRONTEND=noninteractive

PACKAGES=(vim tmux git mergerfs inxi snapraid samba openssl)

missing=()
for pkg in "${PACKAGES[@]}"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        missing+=("$pkg")
    else
        info "$pkg is already installed"
    fi
done

if [ ${#missing[@]} -gt 0 ]; then
    info "Installing packages: ${missing[*]}"
    apt-get update -qq
    apt-get install -y "${missing[@]}"
fi
