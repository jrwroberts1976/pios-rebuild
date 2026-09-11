# Raspberry Pi 4 / CentOS 9 Migration Profile

## Purpose

This project supports a second migration profile in addition to the original Raspberry Pi 3 / CentOS 7 estate:

| Profile | Current platform | Target platform |
| --- | --- | --- |
| Pi 3 legacy | Raspberry Pi 3, CentOS 7 | Debian 13 arm64 |
| Pi 4 current | Raspberry Pi 4, CentOS 9 | Debian 13 arm64 |

The overall migration method is the same for both profiles: protect the active node, rebuild the passive node first, prove the RAM-rescue path non-destructively, retain a full 32 GB rollback image, write the exact tested Debian image, restore FreeSWITCH configuration, test, soak and only then fail production service over.

The Raspberry Pi 4 / CentOS 9 profile must nevertheless be treated as a separate engineering target. A rescue kernel/initramfs/DTB combination proven on a Pi 3 / CentOS 7 node is **not** automatically approved for a Pi 4 / CentOS 9 node.

## Pi 4 profile configuration

Start from:

```text
config/site-pi4-centos9.env.example
```

Copy it to protected storage outside the repository and populate the node-specific IP, MAC, rescue paths and approved Debian checksum.

The profile sets:

```text
EXPECTED_MODEL_REGEX='^Raspberry Pi 4'
EXPECTED_ARCH='aarch64|arm64'
EXPECTED_SOURCE_OS_ID='centos'
EXPECTED_SOURCE_OS_VERSION='9'
TARGET_DISK=/dev/mmcblk0
```

Do not assume `/dev/mmcblk0` merely because the example uses it. The whole-card device must be confirmed by preflight on the actual node before backup or overwrite.

## Required Pi 4 / CentOS 9 preflight evidence

Before designing or loading RAM rescue, record at minimum:

- exact Raspberry Pi 4 model string;
- architecture and running kernel;
- `/etc/os-release` and CentOS release information;
- root filesystem source;
- `/boot` layout;
- kernel, initramfs and DTB files present;
- `CONFIG_KEXEC`/`CONFIG_KEXEC_FILE` capability;
- wired interface name, IP, MAC and default route;
- exact 32 GB SD-card device and partition layout;
- FreeSWITCH version, modules, Sofia profiles and gateway state;
- enabled services, listening sockets and firewall configuration.

The existing `01-preflight.sh`, inventory and FreeSWITCH export stages are intended to capture this evidence. The expected model and source OS values in the Pi 4 profile act as fail-closed identity gates.

## RAM-rescue requirement

Build and validate the rescue environment specifically for the Pi 4 / CentOS 9 combination. It must include the Pi 4 network and SD/MMC support required by the real hardware and must be tested using the sequence:

```text
CentOS 9
  -> load Pi 4 rescue
  -> enter RAM rescue
  -> reconnect over router-hosted VPN
  -> prove RAM-root, network and SD visibility
  -> reboot without writing SD
  -> CentOS 9 returns
```

Only after that exact round trip passes may the Pi 4 profile proceed to a destructive Debian write.

## Debian image validation

The same Debian 13 arm64 golden-image engineering approach can be used for Pi 3 and Pi 4, but production approval is hardware-specific. If the image is to be used on Pi 4, boot the exact checksum-approved image on representative Pi 4 hardware and validate:

- boot and reboot reliability;
- wired Ethernet and expected addressing;
- SSH access;
- storage detection;
- time synchronisation;
- package management;
- FreeSWITCH package/module compatibility;
- required call-flow behaviour.

A pass on Pi 3 alone is not sufficient evidence for the Pi 4 release.

## CentOS 9 configuration migration

Treat CentOS 9 configuration as migration input, not as a filesystem to copy wholesale over Debian. In particular review and translate:

- NetworkManager/network configuration;
- firewalld/nftables policy;
- SELinux-specific configuration;
- RPM package names and repositories;
- custom systemd units;
- cron/timers;
- FreeSWITCH paths, modules, scripts, certificates and runtime data.

The FreeSWITCH configuration export remains separate from the general OS inventory because it is deliberately restored/reconciled on Debian.

## Backup and rollback

The Pi 4 nodes use 32 GB SD cards. Before a destructive write, retain a full raw image of the node being rebuilt and verify its SHA-256 off-node. When retaining both 32 GB node images on the administration laptop, the project release-day recommendation remains **80 GB free space** to provide room for the two rollback images, Debian image, exports, checksums and working files.

Rollback remains:

- before SD overwrite: normal reboot to CentOS 9;
- rescue running, SD untouched: reboot to CentOS 9;
- Debian written while rescue remains alive: write the verified CentOS 9 full-card image back to the same confirmed device;
- Debian booted but not accepted: keep production on the untouched peer and repair/rebuild the passive node.

## Time estimate

Use the same working estimate unless testing proves otherwise:

- first Pi 4 / CentOS 9 passive-node migration: **3-4 hours**;
- subsequent proven migration: approximately **1.5-2.5 hours**, with a **2-3 hour** working allowance sensible;
- soak periods are additional and are not part of the hands-on migration time.

## Release-day selection

At the top of `RELEASE_DAY.md`, record the selected source profile and verify it matches the node:

```text
Migration profile: PI3-CENTOS7 / PI4-CENTOS9
Current OS: CentOS 7 / CentOS 9
Raspberry Pi model: Raspberry Pi 3 / Raspberry Pi 4
```

A profile mismatch is a NO-GO. Do not weaken `EXPECTED_MODEL_REGEX` or the expected source OS values simply to force a migration to proceed.
