#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Build a customised Debian 13 Raspberry Pi arm64 raw image.

Usage:
  sudo ./scripts/00-build-debian-image.sh \
    --source debian-13-raspi-arm64-daily.tar.xz \
    --source-sha512 <official-sha512> \
    --output pios-debian13-arm64.img.xz \
    [--install-freeswitch]

FreeSWITCH package mode requires SIGNALWIRE_TOKEN in the environment. The token
is used only while the image is mounted and is removed before finalisation.

This builder intentionally requires an arm64/aarch64 build host. Cross-arch
emulation is not silently enabled.
EOF
}

fatal() { echo "ERROR: $*" >&2; exit 1; }
log() { printf '[%s] %s\n' "$(date -Is)" "$*"; }

[[ ${EUID:-$(id -u)} -eq 0 ]] || fatal "Run as root."

SOURCE=''
SOURCE_SHA512=''
OUTPUT=''
INSTALL_FS=0

while (($#)); do
  case "$1" in
    --source) SOURCE="${2:-}"; shift 2 ;;
    --source-sha512) SOURCE_SHA512="${2:-}"; shift 2 ;;
    --output) OUTPUT="${2:-}"; shift 2 ;;
    --install-freeswitch) INSTALL_FS=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fatal "Unknown argument: $1" ;;
  esac
done

[[ -f "$SOURCE" ]] || fatal "Source archive not found: $SOURCE"
[[ "$SOURCE_SHA512" =~ ^[0-9a-fA-F]{128}$ ]] || fatal "A 128-character official source SHA512 is required."
[[ -n "$OUTPUT" ]] || fatal "--output is required"
[[ "$(uname -m)" == "aarch64" || "$(uname -m)" == "arm64" ]] || fatal "Builder currently requires an arm64/aarch64 host."

for cmd in sha512sum tar xz losetup lsblk mount umount chroot rsync blkid; do
  command -v "$cmd" >/dev/null 2>&1 || fatal "Required build-host command missing: $cmd"
done

ACTUAL="$(sha512sum "$SOURCE" | awk '{print $1}')"
[[ "${ACTUAL,,}" == "${SOURCE_SHA512,,}" ]] || fatal "Source SHA512 mismatch."
log "Official source checksum PASS"

if [[ "$INSTALL_FS" -eq 1 ]]; then
  [[ -n "${SIGNALWIRE_TOKEN:-}" ]] || fatal "SIGNALWIRE_TOKEN must be supplied in the environment for package installation."
fi

WORK="$(mktemp -d /var/tmp/pios-image-build.XXXXXX)"
RAW="$WORK/disk.raw"
MNT="$WORK/root"
PROBE="$WORK/probe"
mkdir -p "$MNT" "$PROBE"
LOOP=''
ROOT_PART=''
BOOT_PART=''
RESOLV_BACKUP=''
POLICY_CREATED=0

cleanup() {
  set +e
  if mountpoint -q "$MNT/run"; then umount -R "$MNT/run"; fi
  if mountpoint -q "$MNT/sys"; then umount -R "$MNT/sys"; fi
  if mountpoint -q "$MNT/proc"; then umount -R "$MNT/proc"; fi
  if mountpoint -q "$MNT/dev"; then umount -R "$MNT/dev"; fi
  if mountpoint -q "$MNT/boot/firmware"; then umount "$MNT/boot/firmware"; fi
  if mountpoint -q "$MNT"; then umount "$MNT"; fi
  if mountpoint -q "$PROBE"; then umount "$PROBE"; fi
  [[ -n "$LOOP" ]] && losetup -d "$LOOP" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

MEMBER="$(tar -tf "$SOURCE" | grep -E '(^|/)disk\.raw$' | head -1 || true)"
[[ -n "$MEMBER" ]] || fatal "Unable to locate disk.raw inside source archive."
log "Extracting $MEMBER"
tar -xOf "$SOURCE" "$MEMBER" > "$RAW"

LOOP="$(losetup --find --show --partscan "$RAW")"
log "Loop device: $LOOP"
command -v udevadm >/dev/null 2>&1 && udevadm settle || sleep 2

mapfile -t PARTS < <(lsblk -lnpo NAME,TYPE "$LOOP" | awk '$2=="part" {print $1}')
((${#PARTS[@]} > 0)) || fatal "No partitions detected in source image."

for part in "${PARTS[@]}"; do
  if mount -o ro "$part" "$PROBE" 2>/dev/null; then
    if [[ -f "$PROBE/etc/os-release" ]]; then
      ROOT_PART="$part"
    fi
    FSTYPE="$(findmnt -n -o FSTYPE "$PROBE" 2>/dev/null || true)"
    if [[ "$FSTYPE" == "vfat" || "$FSTYPE" == "fat" || "$FSTYPE" == "fat32" ]]; then
      BOOT_PART="$part"
    fi
    umount "$PROBE"
  fi
done

[[ -n "$ROOT_PART" ]] || fatal "Unable to identify Debian root partition."
log "Root partition: $ROOT_PART"
[[ -n "$BOOT_PART" ]] && log "Boot partition: $BOOT_PART"

mount "$ROOT_PART" "$MNT"
if [[ -n "$BOOT_PART" && -d "$MNT/boot/firmware" ]]; then
  mount "$BOOT_PART" "$MNT/boot/firmware"
fi

. "$MNT/etc/os-release"
[[ "${ID:-}" == "debian" && "${VERSION_ID:-}" == "13" ]] || fatal "Source image is not Debian 13."

for d in dev proc sys run; do
  mount --rbind "/$d" "$MNT/$d"
  mount --make-rslave "$MNT/$d"
done

if [[ -e "$MNT/etc/resolv.conf" || -L "$MNT/etc/resolv.conf" ]]; then
  cp -aL "$MNT/etc/resolv.conf" "$WORK/resolv.conf.image" 2>/dev/null || true
  RESOLV_BACKUP="$WORK/resolv.conf.image"
fi
rm -f "$MNT/etc/resolv.conf"
cp -L /etc/resolv.conf "$MNT/etc/resolv.conf"

cat > "$MNT/usr/sbin/policy-rc.d" <<'EOF'
#!/bin/sh
exit 101
EOF
chmod 755 "$MNT/usr/sbin/policy-rc.d"
POLICY_CREATED=1

BASE_PACKAGES=(
  openssh-server sudo ca-certificates curl wget gnupg jq rsync tar xz-utils zstd pv
  util-linux parted fdisk dosfstools e2fsprogs iproute2 iputils-ping dnsutils ethtool
  tcpdump nftables chrony watchdog lsof procps psmisc vim-tiny less bash-completion
)

log "Installing base operational packages"
chroot "$MNT" /usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get update
chroot "$MNT" /usr/bin/env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${BASE_PACKAGES[@]}"

if [[ "$INSTALL_FS" -eq 1 ]]; then
  log "Installing FreeSWITCH packages using temporary SignalWire credentials"
  install -d -m 0755 "$MNT/usr/share/keyrings" "$MNT/etc/apt/auth.conf.d" "$MNT/etc/apt/sources.list.d"

  cat > "$MNT/etc/apt/auth.conf.d/freeswitch.conf" <<EOF
machine freeswitch.signalwire.com login signalwire password ${SIGNALWIRE_TOKEN}
EOF
  chmod 600 "$MNT/etc/apt/auth.conf.d/freeswitch.conf"

  chroot "$MNT" /usr/bin/env TOKEN="$SIGNALWIRE_TOKEN" sh -c '
    wget --http-user=signalwire --http-password="$TOKEN" \
      -O /usr/share/keyrings/signalwire-freeswitch-repo.gpg \
      https://freeswitch.signalwire.com/repo/deb/debian-release/signalwire-freeswitch-repo.gpg
    echo "deb [signed-by=/usr/share/keyrings/signalwire-freeswitch-repo.gpg] https://freeswitch.signalwire.com/repo/deb/debian-release/ trixie main" \
      > /etc/apt/sources.list.d/freeswitch.list
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      freeswitch-meta-default freeswitch-sounds-en-us-callie freeswitch-sounds-music
  '

  rm -f "$MNT/etc/apt/auth.conf.d/freeswitch.conf"
  rm -f "$MNT/etc/apt/sources.list.d/freeswitch.list"
  rm -f "$MNT/usr/share/keyrings/signalwire-freeswitch-repo.gpg"
  chroot "$MNT" apt-get clean
fi

# Enable services offline. Failure is fatal for SSH, warning-only for FreeSWITCH.
systemctl --root="$MNT" enable ssh
if [[ "$INSTALL_FS" -eq 1 ]]; then
  systemctl --root="$MNT" enable freeswitch || log "WARNING: unable to enable freeswitch offline; validate during image test."
fi

rm -f "$MNT/usr/sbin/policy-rc.d"
POLICY_CREATED=0
rm -f "$MNT/etc/resolv.conf"
if [[ -n "$RESOLV_BACKUP" && -f "$RESOLV_BACKUP" ]]; then
  cp -a "$RESOLV_BACKUP" "$MNT/etc/resolv.conf"
else
  printf 'nameserver 1.1.1.1\n' > "$MNT/etc/resolv.conf"
fi

mkdir -p "$MNT/etc/pios-rebuild"
cat > "$MNT/etc/pios-rebuild/image-build.txt" <<EOF
built_at=$(date -Is)
source_file=$(basename "$SOURCE")
source_sha512=$SOURCE_SHA512
freeswitch_preinstalled=$INSTALL_FS
EOF

sync

for d in run sys proc dev; do
  mountpoint -q "$MNT/$d" && umount -R "$MNT/$d"
done
mountpoint -q "$MNT/boot/firmware" && umount "$MNT/boot/firmware"
umount "$MNT"
losetup -d "$LOOP"
LOOP=''

mkdir -p "$(dirname "$OUTPUT")"
log "Compressing output image: $OUTPUT"
xz -T0 -6 -c "$RAW" > "$OUTPUT"
sha512sum "$OUTPUT" > "$OUTPUT.sha512"

MANIFEST="$OUTPUT.manifest.txt"
cat > "$MANIFEST" <<EOF
built_at=$(date -Is)
source=$(basename "$SOURCE")
source_sha512=$SOURCE_SHA512
output=$(basename "$OUTPUT")
output_sha512=$(sha512sum "$OUTPUT" | awk '{print $1}')
freeswitch_preinstalled=$INSTALL_FS
builder_arch=$(uname -m)
EOF

log "IMAGE_BUILD_COMPLETE=YES"
log "output=$OUTPUT"
log "sha512_file=$OUTPUT.sha512"
log "manifest=$MANIFEST"
log "The image is NOT approved for production until docs/TEST_PLAN.md passes."
