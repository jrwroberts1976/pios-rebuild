#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"

require_root
load_config

usage() {
  cat <<'EOF'
Usage:
  06-write-debian.sh --target /dev/mmcblk0 --image /path/image.img.xz --confirm ERASE_CENTOS

or, for a pre-verified raw image streamed over SSH:
  06-write-debian.sh --target /dev/mmcblk0 --stdin-raw --confirm ERASE_CENTOS

The stdin mode assumes the compressed image was checksum-verified on the sending
host and decompressed before entering this script.
EOF
}

TARGET=''
IMAGE=''
STDIN_RAW=0
CONFIRM=''

while (($#)); do
  case "$1" in
    --target) TARGET="${2:-}"; shift 2 ;;
    --image) IMAGE="${2:-}"; shift 2 ;;
    --stdin-raw) STDIN_RAW=1; shift ;;
    --confirm) CONFIRM="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) fatal "Unknown argument: $1" ;;
  esac
done

[[ -n "$TARGET" ]] || fatal "--target is required"
[[ "$TARGET" == "$TARGET_DISK" ]] || fatal "Requested target '$TARGET' does not match configured TARGET_DISK '$TARGET_DISK'."
require_literal_confirmation "$CONFIRM" ERASE_CENTOS
assert_expected_pi
assert_running_from_ram
assert_whole_block_device "$TARGET"
assert_target_unmounted "$TARGET"

if [[ "$STDIN_RAW" -eq 1 && -n "$IMAGE" ]]; then
  fatal "Choose either --image or --stdin-raw, not both."
fi
if [[ "$STDIN_RAW" -eq 0 ]]; then
  [[ -n "$IMAGE" ]] || fatal "--image is required unless --stdin-raw is used."
  [[ -f "$IMAGE" ]] || fatal "Image not found: $IMAGE"
  require_command xz

  if [[ -n "${DEBIAN_IMAGE_SHA512:-}" ]]; then
    ACTUAL="$(sha512_of "$IMAGE")"
    [[ "${ACTUAL,,}" == "${DEBIAN_IMAGE_SHA512,,}" ]] || fatal "Approved Debian image SHA512 mismatch."
    log "Approved image checksum PASS"
  else
    fatal "DEBIAN_IMAGE_SHA512 is not configured. Refusing local image write without approved checksum."
  fi
fi

printf '\n===== DESTRUCTIVE WRITE GATE =====\n'
printf 'model=%s\n' "$(pi_model)"
printf 'root=%s\n' "$(root_source)"
printf 'target=%s\n' "$TARGET"
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT,MODEL,SERIAL "$TARGET"
printf 'confirmation=PASS\n'
printf 'target_unmounted=PASS\n'
printf 'ram_root=PASS\n'

log "Beginning Debian image write. CentOS on $TARGET will be overwritten now."

if [[ "$STDIN_RAW" -eq 1 ]]; then
  dd of="$TARGET" bs=4M iflag=fullblock status=progress conv=fsync
else
  xz -dc "$IMAGE" | dd of="$TARGET" bs=4M iflag=fullblock status=progress conv=fsync
fi

sync
blockdev --flushbufs "$TARGET" 2>/dev/null || true
blockdev --rereadpt "$TARGET" 2>/dev/null || true
partprobe "$TARGET" 2>/dev/null || true
sleep 2

printf '\n===== NEW PARTITION TABLE =====\n'
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT,PARTUUID "$TARGET"
fdisk -l "$TARGET" 2>/dev/null || true

log "DEBIAN_IMAGE_WRITE_COMPLETE=YES"
log "DO NOT REBOOT YET. Mount and configure the new Debian filesystems as described in docs/RUNBOOK.md."
