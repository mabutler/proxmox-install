#!/usr/bin/env bash
set -euo pipefail

pacman -Sy --noconfirm tailscale

tailscale up
