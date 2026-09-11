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
  07a-restore-freeswitch-config.sh \
    --archive /path/to/freeswitch-config.tgz \
    [--dest /etc/freeswitch] \
    --confirm APPLY_FREESWITCH_CONFIG

This script does not install FreeSWITCH packages. It restores the previously
exported configuration onto an already prepared Debian FreeSWITCH installation.
EOF
}

ARCHIVE=''
DEST=''
CONFIRM=''

while (($#)); do
  case "$1" in
    --archive) ARCHIVE="${2:-}"; shift 2 ;;
    --dest) DEST="${2:-}"; shift 2 ;;
    --confirm) CONFIRM="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) fatal "Unknown argument: $1" ;;
  esac
done

[[ -n "$ARCHIVE" ]] || fatal "--archive is required"
[[ -f "$ARCHIVE" ]] || fatal "Archive not found: $ARCHIVE"
require_literal_confirmation "$CONFIRM" APPLY_FREESWITCH_CONFIG

. /etc/os-release 2>/dev/null || fatal "Unable to read /etc/os-release"
[[ "${ID:-}" == "debian" ]] || fatal "This restore script is intended for Debian. Found ID=${ID:-unknown}"
[[ "${VERSION_ID:-}" == "${EXPECTED_DEBIAN_VERSION:-13}" ]] || fatal "Unexpected Debian version: ${VERSION_ID:-unknown}"

if [[ -z "$DEST" ]]; then
  if [[ -d /etc/freeswitch ]]; then
    DEST=/etc/freeswitch
  elif [[ -d /usr/local/freeswitch/conf ]]; then
    DEST=/usr/local/freeswitch/conf
  else
    fatal "Unable to determine Debian FreeSWITCH config destination. Use --dest explicitly."
  fi
fi

[[ -d "$DEST" ]] || fatal "Destination does not exist: $DEST"

CHECKSUM_FILE="$ARCHIVE.sha256"
if [[ -f "$CHECKSUM_FILE" ]]; then
  log "Verifying archive checksum: $CHECKSUM_FILE"
  (cd "$(dirname "$ARCHIVE")" && sha256sum -c "$(basename "$CHECKSUM_FILE")")
else
  fatal "Checksum sidecar missing: $CHECKSUM_FILE"
fi

TMP="$(mktemp -d /var/tmp/pios-fs-restore.XXXXXX)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

tar -xzf "$ARCHIVE" -C "$TMP"

SOURCE=''
if [[ -d "$TMP/etc/freeswitch" ]]; then
  SOURCE="$TMP/etc/freeswitch"
elif [[ -d "$TMP/usr/local/freeswitch/conf" ]]; then
  SOURCE="$TMP/usr/local/freeswitch/conf"
else
  fatal "Archive does not contain a recognised FreeSWITCH config root."
fi

[[ -f "$SOURCE/freeswitch.xml" ]] || fatal "Source config does not contain freeswitch.xml"

TS="$(date +%Y%m%d-%H%M%S)"
BACKUP="/var/tmp/freeswitch-debian-before-restore-$TS.tgz"
tar --xattrs --acls -czf "$BACKUP" "$DEST"
sha256sum "$BACKUP" > "$BACKUP.sha256"
log "Fresh Debian FreeSWITCH config backed up to $BACKUP"

if systemctl list-unit-files freeswitch.service >/dev/null 2>&1; then
  systemctl stop freeswitch || true
fi

require_command rsync
log "Overlaying exported configuration onto $DEST"
rsync -aHAX --delete-delay "$SOURCE/" "$DEST/"

if id freeswitch >/dev/null 2>&1; then
  # Keep configuration readable by the Debian service account while avoiding
  # preservation of potentially different CentOS numeric UIDs/GIDs.
  chown -R root:freeswitch "$DEST" 2>/dev/null || true
  find "$DEST" -type d -exec chmod u+rwx,g+rx {} + 2>/dev/null || true
  find "$DEST" -type f -exec chmod u+rw,g+r {} + 2>/dev/null || true
fi

printf '\n===== RESTORED CONFIG SUMMARY =====\n'
printf 'source=%s\n' "$SOURCE"
printf 'destination=%s\n' "$DEST"
printf 'fresh_debian_backup=%s\n' "$BACKUP"
printf 'xml_files=%s\n' "$(find "$DEST" -type f -name '*.xml' | wc -l)"
printf 'freeswitch_xml=%s\n' "$(test -f "$DEST/freeswitch.xml" && echo PASS || echo FAIL)"

log "FREESWITCH_CONFIG_RESTORED=YES"
log "Do not treat this as service acceptance. Run scripts/08-freeswitch-smoke-test.sh next and resolve any module/package differences."
