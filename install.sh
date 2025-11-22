#!/usr/bin/env bash

set -euo pipefail

LOG_DIR="/var/log/proxmox-install"
mkdir -p "$LOG_DIR"

log() {
	echo "$(date -Iseconds) | $1" | tee -a "$LOG_DIR/setup.log"
}

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"
SECRETS_FILE="$MODULE_DIR/tools/secrets.sh"
export TOOLS_DIR="$MODULE_DIR/tools"
LIB_FILE="$MODULE_DIR/scripts/lib.sh"
if [ -f "$LIB_FILE" ]; then
	# shellcheck source=/dev/null
	source "$LIB_FILE"
fi

log "Starting proxmox setup."

if [ -f "$SECRETS_FILE" ]; then
	# shellcheck source=/dev/null
	source "$SECRETS_FILE"
else
	warn "Secrets file not found: $SECRETS_FILE (continuing)"
fi

while IFS= read -r -d '' module; do
	modname="$(basename "$module")"
	log "Running module: $module"
	bash "$module" 2>&1 | tee "$LOG_DIR/${modname}.log"
	status=${PIPESTATUS[0]}

	if [ "$status" -ne 0 ]; then
		log "ERROR in module: $module"
		log "Stopping setup due to error."
		exit 1
	fi
done < <(find "$MODULE_DIR/scripts" -mindepth 2 -type f -name "*.sh" -print0 | sort -z)

log "Setup completed successfully."
