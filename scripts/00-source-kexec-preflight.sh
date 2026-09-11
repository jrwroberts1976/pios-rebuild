#!/usr/bin/env bash
set -euo pipefail

# Read-only source-OS kexec readiness audit for the existing CentOS Pi.
# This script DOES NOT load or execute a kernel and DOES NOT modify boot/storage.

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "ERROR: run as root so all kernel/boot checks can be inspected." >&2
  exit 1
fi

PASS=0
WARN=0
FAIL=0

pass() { echo "PASS: $*"; PASS=$((PASS + 1)); }
warn() { echo "WARN: $*"; WARN=$((WARN + 1)); }
fail() { echo "FAIL: $*"; FAIL=$((FAIL + 1)); }

KREL="$(uname -r)"
ARCH="$(uname -m)"
MODEL="$(tr -d '\0' </proc/device-tree/model 2>/dev/null || true)"
OS_ID="unknown"
OS_VERSION="unknown"
OS_PRETTY="unknown"

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  OS_ID="${ID:-unknown}"
  OS_VERSION="${VERSION_ID:-unknown}"
  OS_PRETTY="${PRETTY_NAME:-unknown}"
fi

echo "===== SOURCE KEXEC READINESS ====="
printf 'hostname=%s\n' "$(hostname -f 2>/dev/null || hostname)"
printf 'model=%s\n' "${MODEL:-unknown}"
printf 'arch=%s\n' "$ARCH"
printf 'kernel=%s\n' "$KREL"
printf 'os=%s\n' "$OS_PRETTY"
printf 'os_id=%s\n' "$OS_ID"
printf 'os_version=%s\n' "$OS_VERSION"
echo

# 1. Supported source profile.
echo "===== SOURCE PROFILE ====="
if [[ "$OS_ID" == "centos" && "$OS_VERSION" == 7* ]]; then
  pass "CentOS 7 source profile detected (PI3-CENTOS7 candidate)."
  echo "install_hint=yum install -y kexec-tools"
elif [[ "$OS_ID" == "centos" && "$OS_VERSION" == 9* ]]; then
  pass "CentOS 9 source profile detected (PI4-CENTOS9 candidate)."
  echo "install_hint=dnf install -y kexec-tools"
else
  fail "Unsupported/unexpected source OS for this migration project: ID=$OS_ID VERSION_ID=$OS_VERSION"
fi

case "$ARCH" in
  aarch64|arm64)
    pass "64-bit ARM architecture detected: $ARCH"
    ;;
  *)
    fail "Expected aarch64/arm64 for the Debian 13 arm64 migration target; detected $ARCH"
    ;;
esac

if [[ -n "$MODEL" ]]; then
  pass "Raspberry Pi device-tree model is readable: $MODEL"
else
  fail "Unable to read /proc/device-tree/model"
fi

echo

# 2. Userspace kexec tooling.
echo "===== KEXEC TOOL ====="
if command -v kexec >/dev/null 2>&1; then
  KEXEC_BIN="$(command -v kexec)"
  pass "kexec command present: $KEXEC_BIN"
  "$KEXEC_BIN" --version || true
else
  fail "kexec command missing. Install package kexec-tools before continuing."
fi

if command -v rpm >/dev/null 2>&1; then
  if rpm -q kexec-tools >/dev/null 2>&1; then
    pass "RPM package installed: $(rpm -q kexec-tools)"
  else
    fail "RPM package kexec-tools is not installed."
  fi
else
  warn "rpm command not present; package ownership could not be verified."
fi

echo

# 3. Kernel-level kexec configuration evidence.
echo "===== KERNEL KEXEC SUPPORT ====="
CONFIG_SOURCE=""
CONFIG_TEXT=""

if [[ -r "/boot/config-$KREL" ]]; then
  CONFIG_SOURCE="/boot/config-$KREL"
  CONFIG_TEXT="$(grep -E '^CONFIG_KEXEC(=|_)' "$CONFIG_SOURCE" || true)"
elif [[ -r /proc/config.gz ]] && command -v zgrep >/dev/null 2>&1; then
  CONFIG_SOURCE="/proc/config.gz"
  CONFIG_TEXT="$(zgrep -E '^CONFIG_KEXEC(=|_)' /proc/config.gz || true)"
elif [[ -r "/lib/modules/$KREL/build/.config" ]]; then
  CONFIG_SOURCE="/lib/modules/$KREL/build/.config"
  CONFIG_TEXT="$(grep -E '^CONFIG_KEXEC(=|_)' "$CONFIG_SOURCE" || true)"
fi

if [[ -n "$CONFIG_SOURCE" ]]; then
  echo "config_source=$CONFIG_SOURCE"
  if [[ -n "$CONFIG_TEXT" ]]; then
    printf '%s\n' "$CONFIG_TEXT"
  fi

  if grep -Eq '^CONFIG_KEXEC=y$|^CONFIG_KEXEC_FILE=y$' <<<"$CONFIG_TEXT"; then
    pass "Running kernel configuration advertises kexec support."
  else
    fail "Kernel config was found but no CONFIG_KEXEC=y or CONFIG_KEXEC_FILE=y was found."
  fi
else
  warn "Running kernel config is not exposed in the usual locations. A later controlled load/unload test is required to prove syscall support."
fi

if [[ -r /proc/sys/kernel/kexec_load_disabled ]]; then
  KEXEC_DISABLED="$(cat /proc/sys/kernel/kexec_load_disabled)"
  echo "kexec_load_disabled=$KEXEC_DISABLED"
  if [[ "$KEXEC_DISABLED" == "0" ]]; then
    pass "Kernel has not disabled future kexec loads."
  else
    fail "kernel.kexec_load_disabled=$KEXEC_DISABLED; kexec loading is disabled."
  fi
else
  warn "/proc/sys/kernel/kexec_load_disabled is not exposed; this alone does not prove kexec is unavailable."
fi

if [[ -r /sys/kernel/security/lockdown ]]; then
  LOCKDOWN="$(cat /sys/kernel/security/lockdown)"
  echo "lockdown=$LOCKDOWN"
  if grep -Eq '\[(none)\]' <<<"$LOCKDOWN"; then
    pass "Kernel lockdown is not active."
  else
    warn "Kernel lockdown appears active; unsigned kexec images may be restricted: $LOCKDOWN"
  fi
else
  echo "lockdown=not-exposed"
fi

echo

# 4. Exact running-kernel boot artifacts.
echo "===== MATCHING BOOT ARTIFACTS ====="
KERNEL_CANDIDATES=(
  "/boot/vmlinuz-$KREL"
  "/boot/Image-$KREL"
  "/boot/kernel-$KREL.img"
  "/boot/firmware/vmlinuz-$KREL"
  "/boot/firmware/kernel8.img"
)
INITRD_CANDIDATES=(
  "/boot/initramfs-$KREL.img"
  "/boot/initrd.img-$KREL"
  "/boot/initrd-$KREL.img"
  "/boot/firmware/initramfs8"
)

KERNEL_IMAGE=""
for f in "${KERNEL_CANDIDATES[@]}"; do
  if [[ -r "$f" ]]; then
    KERNEL_IMAGE="$f"
    break
  fi
done

INITRD_IMAGE=""
for f in "${INITRD_CANDIDATES[@]}"; do
  if [[ -r "$f" ]]; then
    INITRD_IMAGE="$f"
    break
  fi
done

if [[ -n "$KERNEL_IMAGE" ]]; then
  pass "Readable kernel candidate found: $KERNEL_IMAGE"
  ls -lh "$KERNEL_IMAGE"
else
  warn "No exact kernel candidate was selected automatically. Review /boot manually before any kexec load."
fi

if [[ -n "$INITRD_IMAGE" ]]; then
  pass "Readable initramfs/initrd candidate found: $INITRD_IMAGE"
  ls -lh "$INITRD_IMAGE"
else
  warn "No matching initramfs/initrd candidate was selected automatically. A rescue initramfs must be built/provided before kexec execution."
fi

if [[ -r /sys/firmware/fdt ]]; then
  pass "Live firmware device tree is readable: /sys/firmware/fdt"
  ls -lh /sys/firmware/fdt
else
  warn "Live FDT is not available at /sys/firmware/fdt; the profile-specific DTB must be identified from boot files."
fi

echo
printf '%s\n' "Possible kernel/initramfs/DTB files:" 
find /boot -maxdepth 4 -type f \
  \( -name 'vmlinuz*' -o -name 'Image*' -o -name 'kernel*.img' \
     -o -name 'initramfs*' -o -name 'initrd*' -o -name '*.dtb' \) \
  -print 2>/dev/null | sort || true

echo

# 5. Runtime/network/storage evidence needed for a remote kexec rescue.
echo "===== CURRENT BOOT / NETWORK / STORAGE ====="
echo "cmdline=$(cat /proc/cmdline 2>/dev/null || true)"
printf 'root='; findmnt -n -o SOURCE / 2>/dev/null || true
printf 'root_fstype='; findmnt -n -o FSTYPE / 2>/dev/null || true
ip -br link 2>/dev/null || true
ip -br addr 2>/dev/null || true
ip route 2>/dev/null || true
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT,MODEL,SERIAL 2>/dev/null || true

if ip route 2>/dev/null | grep -q '^default '; then
  pass "Default route is present."
else
  fail "No default route is present."
fi

if command -v sshd >/dev/null 2>&1 || [[ -x /usr/sbin/sshd ]]; then
  pass "OpenSSH server binary is present."
else
  warn "sshd binary was not found in normal locations. Confirm remote SSH access separately."
fi

echo

# 6. Explicitly state what this script has NOT done.
echo "===== NON-DESTRUCTIVE GUARANTEE ====="
echo "kexec_load_attempted=NO"
echo "kexec_execute_attempted=NO"
echo "disk_write_attempted=NO"
echo "boot_files_modified=NO"

echo

echo "===== RESULT ====="
printf 'checks_pass=%d\n' "$PASS"
printf 'checks_warn=%d\n' "$WARN"
printf 'checks_fail=%d\n' "$FAIL"
printf 'detected_kernel_image=%s\n' "${KERNEL_IMAGE:-UNRESOLVED}"
printf 'detected_initrd_image=%s\n' "${INITRD_IMAGE:-UNRESOLVED}"

if [[ "$FAIL" -gt 0 ]]; then
  echo "KEXEC_OS_READY=NO"
  echo "KEXEC_LOAD_UNLOAD_TEST_REQUIRED=YES"
  exit 2
fi

if [[ "$WARN" -gt 0 ]]; then
  echo "KEXEC_OS_READY=PROVISIONAL"
  echo "KEXEC_LOAD_UNLOAD_TEST_REQUIRED=YES"
  echo "NOTE=Resolve warnings and perform the separately gated same-kernel load/unload proof before approving kexec -e."
  exit 0
fi

echo "KEXEC_OS_READY=YES"
echo "KEXEC_LOAD_UNLOAD_TEST_REQUIRED=YES"
echo "NOTE=Static prerequisites pass. A same-kernel load/unload proof is still mandatory before any kexec -e execution."
