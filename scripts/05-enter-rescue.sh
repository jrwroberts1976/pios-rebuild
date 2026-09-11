#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"

require_root
load_config
require_command kexec

CONFIRM="${1:-}"
require_literal_confirmation "$CONFIRM" ENTER_RESCUE

if [[ -r /sys/kernel/kexec_loaded ]]; then
  [[ "$(cat /sys/kernel/kexec_loaded)" == "1" ]] || fatal "No kexec image is currently loaded."
fi

log "About to leave the running CentOS userspace and enter the RAM rescue environment."
log "Expected rescue SSH port: ${RESCUE_SSH_PORT:-2222}"
log "Existing SSH sessions will terminate."
sync
sleep 2
exec kexec -e
