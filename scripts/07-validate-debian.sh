#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"

require_root
load_config

FAIL=0

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; FAIL=1; }

printf '===== DEBIAN VALIDATION =====\n'

if [[ -r /etc/os-release ]]; then
  . /etc/os-release
else
  fail '/etc/os-release missing'
fi

if [[ "${ID:-}" == 'debian' ]]; then pass 'OS is Debian'; else fail "OS is ${ID:-unknown}"; fi
if [[ "${VERSION_ID:-}" == "${EXPECTED_DEBIAN_VERSION:-13}" ]]; then
  pass "Debian version ${VERSION_ID:-unknown}"
else
  fail "Expected Debian ${EXPECTED_DEBIAN_VERSION:-13}, found ${VERSION_ID:-unknown}"
fi

ARCH="$(uname -m)"
if [[ "$ARCH" == 'aarch64' || "$ARCH" == 'arm64' ]]; then pass "architecture=$ARCH"; else fail "unexpected architecture=$ARCH"; fi

MODEL="$(pi_model)"
if [[ "$MODEL" =~ $EXPECTED_MODEL_REGEX ]]; then pass "model=$MODEL"; else fail "unexpected model=$MODEL"; fi

if systemctl is-active --quiet ssh; then pass 'ssh active'; else fail 'ssh inactive'; fi

IFACE="${EXPECTED_INTERFACE:-eth0}"
if ip link show "$IFACE" >/dev/null 2>&1; then
  pass "interface $IFACE exists"
  ip -br addr show dev "$IFACE" || true
else
  fail "interface $IFACE missing"
fi

if ip route | grep -q '^default '; then
  pass 'default route present'
  ip route | grep '^default '
else
  fail 'default route missing'
fi

if [[ -n "${EXPECTED_IP:-}" ]]; then
  if ip -br addr show dev "$IFACE" | grep -Fq "$EXPECTED_IP"; then pass "expected IP present: $EXPECTED_IP"; else fail "expected IP missing: $EXPECTED_IP"; fi
fi

if [[ -n "${EXPECTED_MAC:-}" && -r "/sys/class/net/$IFACE/address" ]]; then
  ACTUAL_MAC="$(cat "/sys/class/net/$IFACE/address")"
  if [[ "${ACTUAL_MAC,,}" == "${EXPECTED_MAC,,}" ]]; then pass "expected MAC present"; else fail "MAC mismatch expected=$EXPECTED_MAC actual=$ACTUAL_MAC"; fi
fi

if getent hosts deb.debian.org >/dev/null 2>&1; then pass 'DNS resolution works'; else fail 'DNS resolution failed'; fi

if ping -c 2 -W 2 1.1.1.1 >/dev/null 2>&1; then pass 'external IP reachability works'; else echo 'WARN: ICMP reachability test failed or is filtered'; fi

if [[ "$(systemctl --failed --no-legend --plain 2>/dev/null | wc -l)" -eq 0 ]]; then
  pass 'no failed systemd units'
else
  fail 'failed systemd units present'
  systemctl --failed --no-pager || true
fi

printf '\n===== STORAGE =====\n'
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT,MODEL,SERIAL
findmnt /
df -hT

printf '\n===== RESOURCE SNAPSHOT =====\n'
uptime
free -h

printf '\n===== RECENT HIGH-PRIORITY LOGS =====\n'
journalctl -p err..alert -b --no-pager | tail -100 || true

printf '\n===== RESULT =====\n'
if [[ "$FAIL" -eq 0 ]]; then
  echo 'DEBIAN_VALIDATION=PASS'
  exit 0
else
  echo 'DEBIAN_VALIDATION=FAIL'
  exit 2
fi
