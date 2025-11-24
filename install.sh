#!/usr/bin/env bash

set -euo pipefail

LOG_DIR="/var/log/proxmox-install"
mkdir -p "$LOG_DIR"

log() {
	echo "$(date -Iseconds) | $1" | tee -a "$LOG_DIR/setup.log"
}

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"
log "Starting proxmox setup."

while IFS= read -r -d '' module; do
	modname="$(basename "$module")"
	log "Running module: $module"
	if command -v script >/dev/null 2>&1; then
		# Run module under a pseudoterminal so interactive installers that
		# require a TTY behave the same as when executed directly.
		# Prevent `script` from reading the loop's stdin (process substitution)
		# by wiring its stdin to the controlling terminal when available,
		# otherwise to /dev/null.
		if exec 3</dev/tty 2>/dev/null; then
			script -q -c "bash \"$module\"" /dev/null <&3 2>&1 | tee "$LOG_DIR/${modname}.log"
			exec 3<&-
		else
			script -q -c "bash \"$module\"" /dev/null < /dev/null 2>&1 | tee "$LOG_DIR/${modname}.log"
		fi
	else
		bash "$module" 2>&1 | tee "$LOG_DIR/${modname}.log"
	fi
	status=${PIPESTATUS[0]}

	if [ "$status" -ne 0 ]; then
		log "ERROR in module: $module"
		log "Stopping setup due to error."
		exit 1
	fi
done < <(find "$MODULE_DIR/scripts" -mindepth 2 -type f -name "*.sh" -print0 | sort -z)

log "Setup completed successfully."
