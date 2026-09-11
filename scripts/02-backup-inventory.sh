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
DIR="$ARTIFACT_DIR/backup-$TS"
mkdir -p "$DIR"
chmod 700 "$DIR"

log "Collecting package/service/network inventories into $DIR"

rpm -qa | sort > "$DIR/rpm-packages.txt" 2>/dev/null || true
systemctl list-unit-files --state=enabled --no-pager > "$DIR/enabled-services.txt" 2>/dev/null || true
systemctl list-timers --all --no-pager > "$DIR/timers.txt" 2>/dev/null || true
ip addr show > "$DIR/ip-address.txt"
ip route show table all > "$DIR/ip-route.txt"
ip rule show > "$DIR/ip-rule.txt" 2>/dev/null || true
ss -lntup > "$DIR/listening-sockets.txt" 2>/dev/null || true
lsblk -f > "$DIR/lsblk.txt"
fdisk -l "$TARGET_DISK" > "$DIR/fdisk-target.txt" 2>/dev/null || true
findmnt -R / > "$DIR/findmnt.txt"

if command -v fs_cli >/dev/null 2>&1; then
  fs_cli -x 'status' > "$DIR/freeswitch-status.txt" 2>&1 || true
  fs_cli -x 'show modules' > "$DIR/freeswitch-modules.txt" 2>&1 || true
  fs_cli -x 'sofia status' > "$DIR/freeswitch-sofia.txt" 2>&1 || true
  fs_cli -x 'sofia status gateway' > "$DIR/freeswitch-gateways.txt" 2>&1 || true
fi

BACKUP_PATHS=(
  /etc
  /root/.ssh
  /var/lib/freeswitch
  /etc/freeswitch
  /usr/local/freeswitch/conf
)

EXISTING=()
for p in "${BACKUP_PATHS[@]}"; do
  [[ -e "$p" ]] && EXISTING+=("$p")
done

if ((${#EXISTING[@]})); then
  tar --xattrs --acls --numeric-owner -czf "$DIR/config-backup.tgz" "${EXISTING[@]}"
  chmod 600 "$DIR/config-backup.tgz"
  sha256sum "$DIR/config-backup.tgz" > "$DIR/config-backup.tgz.sha256"
fi

cat > "$DIR/README-SENSITIVE.txt" <<'EOF'
This directory may contain FreeSWITCH credentials, SSH authorised keys,
network configuration and other sensitive operational information.
Copy it to approved secure storage and do not commit it to Git.
EOF

( cd "$DIR" && sha256sum ./*.txt 2>/dev/null > inventory-files.sha256 || true )

log "Backup/inventory complete: $DIR"
log "This is not the full block-device image. Take the off-node SD image separately as documented in docs/RUNBOOK.md."
