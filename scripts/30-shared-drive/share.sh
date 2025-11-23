#!/usr/bin/env bash
set -euo pipefail

# Load repo helpers if available
TOOLS_LIB="$(cd "$(dirname "$0")/../.." && pwd)/tools/lib.sh"
if [ -f "$TOOLS_LIB" ]; then
    # shellcheck source=/dev/null
    source "$TOOLS_LIB"
fi

STORAGE_DIR="/mnt/storage/media"

info "--- Checking storage directory ---"
if [ ! -d "$STORAGE_DIR" ]; then
    info "Creating $STORAGE_DIR..."
    mkdir -p "$STORAGE_DIR"
else
    info "$STORAGE_DIR exists."
fi

chmod -R 2777 "$STORAGE_DIR"
setfacl -R -d -m u::rwx,g::rwx,o::rwx "$STORAGE_DIR"
info "Storage directory permissions set to 2777 with default ACLs."
