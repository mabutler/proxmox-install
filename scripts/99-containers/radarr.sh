#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/../lib.sh"

NAME="radarr"

if container_exists "$NAME"; then
	setup_generic_container "$NAME" ""
else
	info "Container $NAME does not exist. Add creation URL to this script when ready."
fi
