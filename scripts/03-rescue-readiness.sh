#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"

require_root
load_config
mkdir_artifacts
assert_expected_pi
assert_whole_block_device "$TARGET_DISK"

READY=1
TS="$(date +%Y%m%d-%H%M%S)"
OUT="$ARTIFACT_DIR/rescue-readiness-$TS.txt"
exec > >(tee "$OUT") 2>&1

log "===== RAM RESCUE READINESS ====="

printf 'model=%s\n' "$(pi_model)"
printf 'arch=%s\n' "$(uname -m)"
printf 'kernel=%s\n' "$(uname -r)"
printf 'root=%s\n' "$(root_source)"
printf 'target=%s\n' "$TARGET_DISK"

if command -v kexec >/dev/null 2>&1; then
  echo 'kexec_tool=PASS'
else
  echo 'kexec_tool=FAIL'
  READY=0
fi

KEXEC_CFG=''
if [[ -r "/boot/config-$(uname -r)" ]]; then
  KEXEC_CFG="$(grep -E '^CONFIG_KEXEC(=y|_FILE=y)' "/boot/config-$(uname -r)" || true)"
fi
if [[ -z "$KEXEC_CFG" && -r /proc/config.gz ]]; then
  KEXEC_CFG="$(zgrep -E '^CONFIG_KEXEC(=y|_FILE=y)' /proc/config.gz || true)"
fi

if [[ -n "$KEXEC_CFG" ]]; then
  echo 'kexec_kernel=PASS'
  printf '%s\n' "$KEXEC_CFG"
else
  echo 'kexec_kernel=FAIL'
  READY=0
fi

IFACE="${EXPECTED_INTERFACE:-eth0}"
if [[ -d "/sys/class/net/$IFACE" ]]; then
  echo 'expected_interface=PASS'
  ip -br addr show dev "$IFACE" || true
else
  echo "expected_interface=FAIL ($IFACE missing)"
  READY=0
fi

if ip route | grep -q '^default '; then
  echo 'default_route=PASS'
  ip route | grep '^default ' || true
else
  echo 'default_route=FAIL'
  READY=0
fi

MEM_KB="$(awk '/MemTotal:/ {print $2}' /proc/meminfo)"
if [[ "${MEM_KB:-0}" -ge 500000 ]]; then
  echo "memory=PASS (${MEM_KB}kB)"
else
  echo "memory=WARN (${MEM_KB:-unknown}kB)"
fi

printf '\n===== POSSIBLE KERNEL/INITRD/DTB FILES =====\n'
find /boot -maxdepth 3 -type f \
  \( -name 'vmlinuz*' -o -name 'kernel*.img' -o -name '*.dtb' -o -name 'initramfs*' -o -name 'initrd*' \) \
  -print 2>/dev/null | sort || true

printf '\n===== NETWORK DRIVER =====\n'
ethtool -i "$IFACE" 2>/dev/null || true

printf '\n===== TARGET =====\n'
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT,MODEL,SERIAL "$TARGET_DISK"
fdisk -l "$TARGET_DISK" 2>/dev/null || true

printf '\n===== RESULT =====\n'
if [[ "$READY" -eq 1 ]]; then
  echo 'RESCUE_READY=YES'
  exit 0
else
  echo 'RESCUE_READY=NO'
  exit 2
fi
