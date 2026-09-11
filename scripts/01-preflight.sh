#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"

require_root
load_config
mkdir_artifacts

TS="$(date +%Y%m%d-%H%M%S)"
OUT="$ARTIFACT_DIR/preflight-$TS.txt"

exec > >(tee "$OUT") 2>&1

log "===== PIOS REBUILD PRE-FLIGHT ====="
log "node_role=$NODE_ROLE"

assert_expected_pi
assert_whole_block_device "$TARGET_DISK"

MODEL="$(pi_model)"
ARCH="$(uname -m)"
ROOT="$(root_source)"

printf '\n===== IDENTITY =====\n'
printf 'hostname=%s\n' "$(hostname -f 2>/dev/null || hostname)"
printf 'model=%s\n' "$MODEL"
printf 'arch=%s\n' "$ARCH"
printf 'kernel=%s\n' "$(uname -r)"
printf 'root=%s\n' "$ROOT"
printf 'target=%s\n' "$TARGET_DISK"

printf '\n===== OS =====\n'
cat /etc/os-release 2>/dev/null || true
cat /etc/centos-release 2>/dev/null || true

printf '\n===== STORAGE =====\n'
lsblk -o NAME,MAJ:MIN,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT,MODEL,SERIAL
findmnt /
findmnt /boot 2>/dev/null || true
df -hT

printf '\n===== NETWORK =====\n'
ip -br link
ip -br addr
ip route
printf '\nDNS:\n'
cat /etc/resolv.conf 2>/dev/null || true

printf '\n===== MAC ADDRESSES =====\n'
for address in /sys/class/net/*/address; do
  iface="$(basename "$(dirname "$address")")"
  printf '%s=%s\n' "$iface" "$(cat "$address")"
done

printf '\n===== FREESWITCH =====\n'
command -v freeswitch || true
command -v fs_cli || true
freeswitch -version 2>/dev/null || true
fs_cli -x 'status' 2>/dev/null || true
fs_cli -x 'show modules' 2>/dev/null || true
fs_cli -x 'sofia status' 2>/dev/null || true
fs_cli -x 'sofia status gateway' 2>/dev/null || true

printf '\n===== KEXEC =====\n'
command -v kexec || true
if [[ -r "/boot/config-$(uname -r)" ]]; then
  grep -E '^CONFIG_KEXEC(=|_)' "/boot/config-$(uname -r)" || true
fi
if [[ -r /proc/config.gz ]]; then
  zgrep -E '^CONFIG_KEXEC(=|_)' /proc/config.gz || true
fi

printf '\n===== BOOT FILES =====\n'
find /boot -maxdepth 3 -type f \
  \( -name 'vmlinuz*' -o -name 'kernel*.img' -o -name '*.dtb' -o -name 'initramfs*' -o -name 'initrd*' \) \
  -print 2>/dev/null | sort || true

printf '\n===== WATCHDOG =====\n'
ls -l /dev/watchdog* 2>/dev/null || true
lsmod | grep -Ei 'wdt|watchdog' || true
dmesg | grep -i watchdog | tail -20 || true

printf '\n===== FAILED SERVICES =====\n'
systemctl --failed --no-pager 2>/dev/null || true

printf '\n===== RESULT =====\n'
printf 'PRECHECK_COMPLETE=YES\n'
printf 'artifact=%s\n' "$OUT"
log "No disk or boot configuration changes were made."
