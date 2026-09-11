#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

CONFIG_FILE="${PIOS_CONFIG:-${REPO_ROOT}/config/site.env}"

log() {
  printf '[%s] %s\n' "$(date -Is)" "$*"
}

fatal() {
  printf '[%s] ERROR: %s\n' "$(date -Is)" "$*" >&2
  exit 1
}

require_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || fatal "Run as root."
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fatal "Required command missing: $1"
}

load_config() {
  [[ -f "$CONFIG_FILE" ]] || fatal "Config not found: $CONFIG_FILE. Copy config/site.env.example and populate it first."
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"

  : "${NODE_ROLE:?NODE_ROLE must be set}"
  : "${EXPECTED_MODEL_REGEX:?EXPECTED_MODEL_REGEX must be set}"
  : "${TARGET_DISK:?TARGET_DISK must be set}"
  : "${ARTIFACT_DIR:=/var/tmp/pios-rebuild}"
}

pi_model() {
  tr -d '\0' </proc/device-tree/model 2>/dev/null || true
}

assert_expected_pi() {
  local model
  model="$(pi_model)"
  [[ -n "$model" ]] || fatal "Unable to read Raspberry Pi model."
  [[ "$model" =~ $EXPECTED_MODEL_REGEX ]] || fatal "Hardware mismatch: '$model' does not match '$EXPECTED_MODEL_REGEX'."
  log "Hardware gate PASS: $model"
}

assert_whole_block_device() {
  local dev="$1"
  [[ -b "$dev" ]] || fatal "Target is not a block device: $dev"

  local type
  type="$(lsblk -ndo TYPE "$dev" 2>/dev/null || true)"
  [[ "$type" == "disk" ]] || fatal "Target must be a whole disk, not a partition: $dev (type=$type)"
}

assert_target_unmounted() {
  local dev="$1"
  local mounted
  mounted="$(lsblk -nrpo NAME,MOUNTPOINT "$dev" | awk '$2 != "" {print}')"
  [[ -z "$mounted" ]] || fatal "Target or a child partition is mounted:\n$mounted"
}

root_source() {
  findmnt -n -o SOURCE /
}

assert_running_from_ram() {
  local root fstype
  root="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
  fstype="$(findmnt -n -o FSTYPE / 2>/dev/null || true)"

  case "$fstype" in
    tmpfs|ramfs|rootfs|overlay)
      log "RAM-root gate PASS: source=${root:-unknown} fstype=$fstype"
      ;;
    *)
      fatal "Root filesystem does not look RAM-resident: source=${root:-unknown} fstype=${fstype:-unknown}"
      ;;
  esac
}

sha512_of() {
  sha512sum "$1" | awk '{print $1}'
}

require_literal_confirmation() {
  local supplied="${1:-}"
  local expected="$2"
  [[ "$supplied" == "$expected" ]] || fatal "Destructive confirmation missing. Expected literal: $expected"
}

mkdir_artifacts() {
  mkdir -p "$ARTIFACT_DIR"
  chmod 700 "$ARTIFACT_DIR"
}
