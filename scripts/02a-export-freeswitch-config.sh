#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"

require_root
load_config
mkdir_artifacts
assert_expected_pi

TS="$(date +%Y%m%d-%H%M%S)"
OUTDIR="$ARTIFACT_DIR/freeswitch-export-$TS"
mkdir -p "$OUTDIR"
chmod 700 "$OUTDIR"

log "===== FREESWITCH CONFIG EXPORT ====="

CONFIG_ROOT=""
for candidate in /etc/freeswitch /usr/local/freeswitch/conf; do
  if [[ -d "$candidate" ]]; then
    CONFIG_ROOT="$candidate"
    break
  fi
done

[[ -n "$CONFIG_ROOT" ]] || fatal "No supported FreeSWITCH configuration root found."

printf 'config_root=%s\n' "$CONFIG_ROOT" > "$OUTDIR/manifest.txt"
printf 'hostname=%s\n' "$(hostname -f 2>/dev/null || hostname)" >> "$OUTDIR/manifest.txt"
printf 'exported_at=%s\n' "$(date -Is)" >> "$OUTDIR/manifest.txt"
printf 'os_id=' >> "$OUTDIR/manifest.txt"
. /etc/os-release 2>/dev/null || true
printf '%s\n' "${ID:-unknown}" >> "$OUTDIR/manifest.txt"
printf 'os_version=%s\n' "${VERSION_ID:-unknown}" >> "$OUTDIR/manifest.txt"
printf 'arch=%s\n' "$(uname -m)" >> "$OUTDIR/manifest.txt"

if command -v freeswitch >/dev/null 2>&1; then
  freeswitch -version > "$OUTDIR/freeswitch-version.txt" 2>&1 || true
fi

if command -v fs_cli >/dev/null 2>&1; then
  fs_cli -x 'status' > "$OUTDIR/freeswitch-status.txt" 2>&1 || true
  fs_cli -x 'show modules' > "$OUTDIR/freeswitch-modules.txt" 2>&1 || true
  fs_cli -x 'sofia status' > "$OUTDIR/freeswitch-sofia-status.txt" 2>&1 || true
  fs_cli -x 'sofia status gateway' > "$OUTDIR/freeswitch-gateways.txt" 2>&1 || true
  fs_cli -x 'global_getvar' > "$OUTDIR/freeswitch-global-vars.txt" 2>&1 || true
fi

if command -v rpm >/dev/null 2>&1; then
  rpm -qa | grep -i '^freeswitch\|freeswitch' | sort > "$OUTDIR/freeswitch-packages.txt" || true
elif command -v dpkg-query >/dev/null 2>&1; then
  dpkg-query -W -f='${binary:Package}\t${Version}\n' '*freeswitch*' 2>/dev/null \
    | sort > "$OUTDIR/freeswitch-packages.txt" || true
fi

# Record referenced module names from autoload_configs where possible.
grep -RhoE 'module="[^"]+"|module name="[^"]+"' \
  "$CONFIG_ROOT"/autoload_configs 2>/dev/null \
  | sed -E 's/.*module( name)?="([^"]+)".*/\2/' \
  | sort -u > "$OUTDIR/config-referenced-modules.txt" || true

# Capture likely certificate and script references without dereferencing secrets.
find "$CONFIG_ROOT" -type f \( -name '*.xml' -o -name '*.conf' -o -name '*.lua' -o -name '*.js' -o -name '*.py' \) \
  -print > "$OUTDIR/config-file-list.txt"

ARCHIVE="$OUTDIR/freeswitch-config.tgz"
tar --xattrs --acls --numeric-owner -czf "$ARCHIVE" "$CONFIG_ROOT"
chmod 600 "$ARCHIVE"
sha256sum "$ARCHIVE" > "$ARCHIVE.sha256"

# Capture common supplementary paths separately if they exist.
SUPP=()
for path in \
  /var/lib/freeswitch \
  /usr/share/freeswitch \
  /usr/local/freeswitch/scripts \
  /var/www/freeswitch; do
  [[ -e "$path" ]] && SUPP+=("$path")
done

if ((${#SUPP[@]})); then
  tar --xattrs --acls --numeric-owner -czf "$OUTDIR/freeswitch-supplementary.tgz" "${SUPP[@]}"
  chmod 600 "$OUTDIR/freeswitch-supplementary.tgz"
  sha256sum "$OUTDIR/freeswitch-supplementary.tgz" > "$OUTDIR/freeswitch-supplementary.tgz.sha256"
fi

cat > "$OUTDIR/README-SENSITIVE.txt" <<'EOF'
This export may contain SIP credentials, event-socket passwords, TLS material,
provider details and other production secrets. Store it securely. Do not commit
this directory or its archives to GitHub.
EOF

( cd "$OUTDIR" && sha256sum ./*.txt 2>/dev/null > metadata.sha256 || true )

log "FREESWITCH_EXPORT_COMPLETE=YES"
log "config_root=$CONFIG_ROOT"
log "archive=$ARCHIVE"
log "Copy the entire export directory off-node before rebuilding the Pi."
