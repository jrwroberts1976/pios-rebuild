# Debian 13 Raspberry Pi Golden Image Build

## Purpose

The remote rebuild must not begin with an untested stock image. A prerequisite is to create and validate a reproducible Debian 13 arm64 Raspberry Pi image containing the operational tools needed at the site and, where credentials are available at build time, the required FreeSWITCH packages.

The image build is deliberately separate from the remote migration. We build once, checksum it, test the exact artifact, and then stream that same artifact to the passive node.

## Source image

Use the official Debian 13 Raspberry Pi arm64 image from Debian Cloud Images.

Reference:
- https://wiki.debian.org/RaspberryPiImages
- https://cloud.debian.org/images/cloud/

Pin and record:

- source URL;
- source filename;
- source SHA512;
- build date;
- repository commit used to customise it;
- output SHA256/SHA512.

Never build from an unrecorded `latest` URL and later assume the output is identical.

## Build host

Preferred build host: an arm64 Debian machine. Building on arm64 avoids cross-architecture chroot complications. The image-builder script fails closed on a non-arm64 build host unless cross-build support is deliberately added later.

## Base packages

The image should contain at least:

- openssh-server
- sudo
- ca-certificates
- curl
- wget
- gnupg
- jq
- rsync
- tar
- xz-utils
- zstd
- pv
- util-linux
- parted
- fdisk
- dosfstools
- e2fsprogs
- iproute2
- iputils-ping
- dnsutils
- ethtool
- tcpdump
- nftables
- chrony
- watchdog
- lsof
- procps
- psmisc
- vim-tiny
- less
- bash-completion

Additional site-specific monitoring/logging packages can be added once the current nodes have been inventoried.

## FreeSWITCH

FreeSWITCH 1.11.0 added Debian 13 Trixie support. The upstream packaging metadata includes arm64, but the exact package set required by the current installation must be established from the CentOS configuration and module inventory.

References:
- https://developer.signalwire.com/freeswitch/foundations/getting-started/
- https://github.com/signalwire/freeswitch/releases

### Preferred package approach

Use the official SignalWire Debian repository where practical.

The binary repository requires a SignalWire Personal Access Token. The token must be passed only at build time and must not remain in the resulting image, shell history, repository, manifest, apt configuration or logs.

The image build should:

1. receive the token through an environment variable or secret file;
2. create temporary apt authentication;
3. install the selected FreeSWITCH packages;
4. remove the apt authentication file;
5. clear apt caches/history that could contain credentials;
6. verify the token is absent from the mounted image before finalising it.

If a packaged install is not suitable, a source-build path can be added as a separate, pinned build mode. Do not silently switch between package and source builds.

## Secrets

Do not bake any of the following into the golden image:

- SIP trunk passwords;
- SignalWire PAT;
- SSH private keys;
- VPN credentials;
- production API tokens;
- production TLS private keys;
- FreeSWITCH event-socket passwords used in production.

Node-specific secrets and configuration are applied after the image is written, while the RAM rescue is still active or through an approved configuration-management step after first boot.

## Node-specific values

Do not permanently bake these into the shared image:

- hostname;
- production IP address;
- active/passive role;
- SIP credentials;
- node-specific certificates.

The same tested base image should be usable for both Pi nodes.

## Image validation

Before the image is approved for remote use:

1. verify the output checksum;
2. verify the partition table is readable;
3. mount the root filesystem and verify `/etc/os-release` reports Debian 13;
4. confirm SSH is installed and enabled;
5. confirm expected administration tools are installed;
6. if FreeSWITCH is baked in, confirm binaries/modules are present;
7. scan the image for known build-time secret values;
8. boot the image on representative Pi 3 hardware where available;
9. perform at least two reboot tests;
10. run the FreeSWITCH test plan against the exact image artifact.

## Artifact naming

Suggested naming convention:

```text
pios-debian13-arm64-YYYYMMDD-<git-short-sha>.img.xz
pios-debian13-arm64-YYYYMMDD-<git-short-sha>.img.xz.sha512
pios-debian13-arm64-YYYYMMDD-<git-short-sha>.manifest.txt
```

The image used on the passive production node must match the checksum recorded in the test evidence.