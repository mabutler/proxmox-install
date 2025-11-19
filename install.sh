#!/usr/bin/env bash

set -euo pipefail

LOG_DIR="/var/log/proxmox-install"
mkdir -p "$LOG_DIR"

log() {
	echo "$(date -Iseconds) | $1" | tee -a "$LOG_DIR/setup.log"
}

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"

log "Starting proxmox setup."

for module in $(find "$MODULE_DIR" -mindepth 2 -type f -name "*.sh" | sort); do
	log "Running module: $module"
	bash "$module" 2>&1 | tee "$LOG_DIR/module.log"
	status=${PIPESTATUS[0]}

	if [ $status -ne 0 ]; then
		log "ERROR in module: $module"
		log "Stopping setup due to error."
		exit 1
	fi
done

log "Setup completed successfully."
