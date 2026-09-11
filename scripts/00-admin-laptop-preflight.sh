#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/00-admin-laptop-preflight.sh \
    --router <ip> \
    --active <user@ip> \
    --passive <user@ip> \
    [--min-free-gb <gb>]

This script is non-destructive. It checks the administration workstation,
required CLI tools, local storage and SSH/VPN reachability assumptions.
EOF
}

ROUTER=''
ACTIVE=''
PASSIVE=''
MIN_FREE_GB=64

while (($#)); do
  case "$1" in
    --router) ROUTER="${2:-}"; shift 2 ;;
    --active) ACTIVE="${2:-}"; shift 2 ;;
    --passive) PASSIVE="${2:-}"; shift 2 ;;
    --min-free-gb) MIN_FREE_GB="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$ROUTER" && -n "$ACTIVE" && -n "$PASSIVE" ]] || { usage; exit 2; }
[[ "$MIN_FREE_GB" =~ ^[0-9]+$ ]] || { echo 'ERROR: --min-free-gb must be numeric' >&2; exit 2; }

FAIL=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; FAIL=1; }
warn() { echo "WARN: $*"; }

printf '===== ADMIN LAPTOP PRE-FLIGHT =====\n'
printf 'host=%s\n' "$(hostname 2>/dev/null || true)"
printf 'kernel=%s\n' "$(uname -srmo 2>/dev/null || uname -a)"

printf '\n===== REQUIRED TOOLS =====\n'
TOOLS=(ssh scp rsync git curl wget tar gzip xz zstd sha256sum sha512sum dd pv awk sed grep find)
for cmd in "${TOOLS[@]}"; do
  if command -v "$cmd" >/dev/null 2>&1; then
    pass "$cmd"
  else
    fail "$cmd missing"
  fi
done

printf '\n===== OPTIONAL TOOLS =====\n'
for cmd in jq nc traceroute mtr tmux screen; do
  if command -v "$cmd" >/dev/null 2>&1; then
    pass "$cmd"
  else
    warn "$cmd not installed"
  fi
done

printf '\n===== LOCAL STORAGE =====\n'
FREE_KB="$(df -Pk . | awk 'NR==2 {print $4}')"
FREE_GB=$((FREE_KB / 1024 / 1024))
printf 'free_gb=%s\n' "$FREE_GB"
printf 'required_free_gb=%s\n' "$MIN_FREE_GB"
if (( FREE_GB >= MIN_FREE_GB )); then
  pass "local free space ${FREE_GB}GB"
else
  fail "only ${FREE_GB}GB free; require at least ${MIN_FREE_GB}GB for this run"
fi

printf '\n===== REPOSITORY =====\n'
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  pass 'running inside a Git work tree'
  printf 'repo=%s\n' "$(git remote get-url origin 2>/dev/null || echo unknown)"
  printf 'commit=%s\n' "$(git rev-parse HEAD)"
  if [[ -z "$(git status --porcelain)" ]]; then
    pass 'working tree clean'
  else
    warn 'working tree contains local modifications; record/review them before migration'
    git status --short
  fi
else
  fail 'not running from a Git work tree'
fi

printf '\n===== VPN/SITE REACHABILITY =====\n'
if command -v ping >/dev/null 2>&1; then
  if ping -c 2 -W 2 "$ROUTER" >/dev/null 2>&1; then
    pass "router reachable: $ROUTER"
  else
    warn "router did not answer ICMP: $ROUTER (may be intentionally filtered)"
  fi
fi

SSH_OPTS=(
  -o BatchMode=yes
  -o ConnectTimeout=8
  -o ServerAliveInterval=5
  -o ServerAliveCountMax=3
)

check_ssh() {
  local target="$1" role="$2"
  if ssh "${SSH_OPTS[@]}" "$target" 'printf "hostname="; hostname; printf "uptime="; uptime' >/tmp/pios-admin-preflight.$$ 2>&1; then
    pass "$role SSH: $target"
    cat /tmp/pios-admin-preflight.$$
  else
    fail "$role SSH failed: $target"
    cat /tmp/pios-admin-preflight.$$ || true
  fi
  rm -f /tmp/pios-admin-preflight.$$
}

check_ssh "$ACTIVE" active
check_ssh "$PASSIVE" passive

printf '\n===== ROUTES =====\n'
if command -v ip >/dev/null 2>&1; then
  ip route 2>/dev/null || true
else
  warn '`ip` command unavailable; inspect VPN routes manually'
fi

printf '\n===== MANUAL GATES =====\n'
echo 'MANUAL: laptop connected to mains power'
echo 'MANUAL: sleep/hibernate disabled for maintenance window'
echo 'MANUAL: VPN reconnect credentials available'
echo 'MANUAL: local artifact directory is on protected/encrypted storage where practical'
echo 'MANUAL: sufficient space is based on actual SD capacities, not only the default threshold'

printf '\n===== RESULT =====\n'
if [[ "$FAIL" -eq 0 ]]; then
  echo 'ADMIN_LAPTOP_PREFLIGHT=PASS'
  exit 0
else
  echo 'ADMIN_LAPTOP_PREFLIGHT=FAIL'
  exit 2
fi
