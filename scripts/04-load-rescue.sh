#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"

require_root
load_config
assert_expected_pi
require_command kexec

: "${RESCUE_KERNEL:?RESCUE_KERNEL must be set in site.env}"
: "${RESCUE_INITRD:?RESCUE_INITRD must be set in site.env}"
: "${RESCUE_CMDLINE:?RESCUE_CMDLINE must be set in site.env}"

[[ -f "$RESCUE_KERNEL" ]] || fatal "Rescue kernel not found: $RESCUE_KERNEL"
[[ -f "$RESCUE_INITRD" ]] || fatal "Rescue initrd not found: $RESCUE_INITRD"
if [[ -n "${RESCUE_DTB:-}" ]]; then
  [[ -f "$RESCUE_DTB" ]] || fatal "Rescue DTB not found: $RESCUE_DTB"
fi

log "Running rescue readiness gate first."
"$HERE/03-rescue-readiness.sh"

ARGS=( -l "$RESCUE_KERNEL" --initrd="$RESCUE_INITRD" --append="$RESCUE_CMDLINE" )
if [[ -n "${RESCUE_DTB:-}" ]]; then
  ARGS+=( --dtb="$RESCUE_DTB" )
fi

log "Loading rescue into kexec slot. This does NOT execute the rescue environment."
kexec "${ARGS[@]}"

if [[ -r /sys/kernel/kexec_loaded ]]; then
  STATE="$(cat /sys/kernel/kexec_loaded)"
  [[ "$STATE" == "1" ]] || fatal "Kernel did not report a loaded kexec image (state=$STATE)."
fi

log "RESCUE_LOADED=YES"
log "No reboot or kexec execution has occurred. Review settings before scripts/05-enter-rescue.sh."
