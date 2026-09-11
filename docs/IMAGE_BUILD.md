# Debian 13 Raspberry Pi Golden Image Build

## Purpose

The remote rebuild must not begin with an untested stock image. A prerequisite is to create and validate a reproducible Debian 13 arm64 Raspberry Pi image containing the operational tools needed at the site and, where credentials are available at build time, the required FreeSWITCH packages.

The image build is deliberately separate from the remote migration. We build once, checksum it, test the exact artifact, and then stream that same artifact to the passive node.

## Supported hardware profiles

The project currently targets:

| Profile | Source hardware / OS | Target |
| --- | --- | --- |
| `PI3-CENTOS7` | Raspberry Pi 3 / CentOS 7 | Debian 13 arm64 |
| `PI4-CENTOS9` | Raspberry Pi 4 / CentOS 9 | Debian 13 arm64 |

The same Debian arm64 image may be usable across both hardware families, but **approval is hardware-specific**. If the artifact will be deployed to both Pi 3 and Pi 4, the exact output checksum must be boot-tested on representative hardware of both families.

## Source image

Use the official Debian 13 Raspberry Pi arm64 image from Debian Cloud Images.

Reference:
- https://wiki.debian.org/RaspberryPiImages
- https://cloud.debian.org/images/cloud/

Pin and record source URL, source filename, source SHA512, build date, repository commit used to customise it and output SHA256/SHA512. Never build from an unrecorded `latest` URL and later assume the output is identical.

## Build host

Preferred build host: an arm64 Debian machine. Building on arm64 avoids cross-architecture chroot complications. The image-builder script fails closed on a non-arm64 build host unless cross-build support is deliberately added later.

## Base packages

The image should contain at least:

```text
openssh-server
sudo
ca-certificates
curl
wget
gnupg
jq
rsync
tar
xz-utils
zstd
pv
util-linux
parted
fdisk
dosfstools
e2fsprogs
iproute2
iputils-ping
dnsutils
ethtool
tcpdump
nftables
chrony
watchdog
lsof
procps
psmisc
vim-tiny
less
bash-completion
```

Additional site-specific monitoring/logging packages can be added once the current nodes have been inventoried.

## FreeSWITCH

FreeSWITCH 1.11.x supports Debian 13/Trixie packaging paths, but the exact package set required by the current installation must be established from the CentOS configuration and module inventory.

References:
- https://developer.signalwire.com/freeswitch/foundations/getting-started/
- https://github.com/signalwire/freeswitch/releases

### Preferred package approach

Use the official SignalWire Debian repository where practical. Any repository token must be passed only at build time and must not remain in the resulting image, shell history, repository, manifest, apt configuration or logs.

The image build should receive the token through an environment variable or secret file, create temporary apt authentication, install the selected FreeSWITCH packages, remove authentication material, clear relevant caches/history and verify the token is absent before finalisation.

If a packaged install is not suitable, a source-build path can be added as a separate, pinned build mode. Do not silently switch between package and source builds.

## Secrets

Do not bake SIP trunk passwords, SignalWire tokens, SSH private keys, VPN credentials, production API tokens, production TLS private keys or FreeSWITCH event-socket passwords into the golden image.

Node-specific secrets and configuration are applied after the image is written, while RAM rescue is still active or through an approved configuration-management step after first boot.

## Node-specific values

Do not permanently bake hostname, production IP, active/passive role, SIP credentials or node-specific certificates into the shared image. The same tested base image should be usable for both nodes within a profile.

## Hardware-specific validation

### Raspberry Pi 3 / CentOS 7 target

Before approval for `PI3-CENTOS7`, boot the exact output image on representative Raspberry Pi 3 hardware and validate wired Ethernet, SSH, storage, time synchronisation, package management, FreeSWITCH and repeated reboot behaviour.

### Raspberry Pi 4 / CentOS 9 target

Before approval for `PI4-CENTOS9`, boot the exact output image on representative Raspberry Pi 4 hardware and validate the same items. Also confirm the Pi 4 firmware/boot files, Ethernet and SD/MMC storage behave as expected on the exact hardware used by the site.

A successful Pi 3 boot test is not sufficient evidence for Pi 4 deployment.

## Image validation

Before the image is approved for remote use:

1. verify the output checksum;
2. verify the partition table is readable;
3. mount the root filesystem and verify `/etc/os-release` reports Debian 13;
4. confirm SSH is installed and enabled;
5. confirm expected administration tools are installed;
6. if FreeSWITCH is baked in, confirm binaries/modules are present;
7. scan the image for known build-time secret values;
8. boot the exact image on representative hardware for each intended profile;
9. perform at least two reboot tests on each intended hardware family;
10. run the FreeSWITCH test plan against the exact image artifact.

## Rescue compatibility is separate

Golden-image approval does not approve the RAM-rescue environment. Pi 3 / CentOS 7 and Pi 4 / CentOS 9 each require their own proven rescue round-trip test because the running CentOS kernel, boot layout, DTB and hardware drivers may differ.

## Artifact naming

Suggested naming convention:

```text
pios-debian13-arm64-YYYYMMDD-<git-short-sha>.img.xz
pios-debian13-arm64-YYYYMMDD-<git-short-sha>.img.xz.sha512
pios-debian13-arm64-YYYYMMDD-<git-short-sha>.manifest.txt
```

The image used on the passive production node must match the checksum recorded in the test evidence for that hardware profile.
