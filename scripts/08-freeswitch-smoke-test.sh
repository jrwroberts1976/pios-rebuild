#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"

require_root
load_config

START=0
if [[ "${1:-}" == '--start' ]]; then
  START=1
elif [[ $# -gt 0 ]]; then
  fatal "Usage: $0 [--start]"
fi

FAIL=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; FAIL=1; }

printf '===== FREESWITCH SMOKE TEST =====\n'

. /etc/os-release 2>/dev/null || true
[[ "${ID:-}" == debian ]] && pass 'OS is Debian' || fail "OS is ${ID:-unknown}"
[[ "${VERSION_ID:-}" == "${EXPECTED_DEBIAN_VERSION:-13}" ]] && pass "Debian ${VERSION_ID:-unknown}" || fail "Unexpected Debian version ${VERSION_ID:-unknown}"

command -v freeswitch >/dev/null 2>&1 && pass 'freeswitch binary present' || fail 'freeswitch binary missing'
command -v fs_cli >/dev/null 2>&1 && pass 'fs_cli present' || fail 'fs_cli missing'

if command -v freeswitch >/dev/null 2>&1; then
  VERSION="$(freeswitch -version 2>&1 | head -1 || true)"
  echo "version=$VERSION"
  if [[ -n "${EXPECTED_FREESWITCH_MAJOR_MINOR:-}" ]]; then
    [[ "$VERSION" == *"${EXPECTED_FREESWITCH_MAJOR_MINOR}"* ]] \
      && pass "FreeSWITCH version matches ${EXPECTED_FREESWITCH_MAJOR_MINOR}" \
      || fail "FreeSWITCH version does not match expected ${EXPECTED_FREESWITCH_MAJOR_MINOR}"
  fi
fi

if [[ "$START" -eq 1 ]]; then
  log 'Starting/restarting FreeSWITCH for smoke test.'
  systemctl restart freeswitch || true
  sleep 3
fi

if systemctl is-active --quiet freeswitch; then
  pass 'freeswitch service active'
else
  fail 'freeswitch service inactive'
  systemctl --no-pager --full status freeswitch || true
fi

if command -v fs_cli >/dev/null 2>&1 && systemctl is-active --quiet freeswitch; then
  if fs_cli -x 'status' >/tmp/pios-fs-status.$$ 2>&1; then
    pass 'fs_cli status succeeded'
    cat /tmp/pios-fs-status.$$
  else
    fail 'fs_cli status failed'
    cat /tmp/pios-fs-status.$$ || true
  fi
  rm -f /tmp/pios-fs-status.$$

  printf '\n===== MODULES =====\n'
  fs_cli -x 'show modules' || fail 'show modules failed'

  printf '\n===== SOFIA STATUS =====\n'
  fs_cli -x 'sofia status' || fail 'sofia status failed'

  printf '\n===== GATEWAYS =====\n'
  fs_cli -x 'sofia status gateway' || fail 'gateway status failed'

  printf '\n===== REGISTRATIONS =====\n'
  fs_cli -x 'show registrations' || true
fi

printf '\n===== LISTENING SOCKETS =====\n'
ss -lntup | grep -E 'freeswitch|:5060|:5061|:5080|:8021' || true

printf '\n===== SERVICE LOGS =====\n'
journalctl -u freeswitch -b --no-pager | tail -150 || true

printf '\n===== SYSTEM HEALTH =====\n'
uptime
free -h
systemctl --failed --no-pager || true

printf '\n===== RESULT =====\n'
if [[ "$FAIL" -eq 0 ]]; then
  echo 'FREESWITCH_SMOKE_TEST=PASS'
  echo 'NOTE: This is only the platform smoke test. Complete docs/FREESWITCH_TEST_PLAN.md before failover.'
  exit 0
else
  echo 'FREESWITCH_SMOKE_TEST=FAIL'
  exit 2
fi
