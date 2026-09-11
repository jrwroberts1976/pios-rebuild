# Admin Laptop Prerequisites

## Purpose

The remote rebuild depends on the engineer's laptop remaining a reliable control point throughout backup, RAM-rescue, image streaming, validation and rollback. The laptop therefore has its own formal prerequisite gate before either Raspberry Pi is touched.

## Supported working environment

Preferred:

- Linux laptop; or
- Windows laptop using WSL2 with an Ubuntu/Debian environment; or
- macOS with equivalent command-line tools installed.

The VPN client itself may run natively on Windows/macOS. The key requirement is that the shell used for the migration can reach both Pi nodes through the established VPN.

## Required network access

Before starting, the laptop must be able to:

- establish the site VPN reliably;
- reach the remote router over the VPN;
- reach both Raspberry Pi management IPs;
- SSH to both CentOS nodes before migration;
- later SSH to the RAM rescue port, default TCP/2222;
- later SSH to Debian on TCP/22;
- resolve/download approved Debian and FreeSWITCH packages where required;
- maintain the VPN route while one Pi is rebooted.

Recommended tests:

```bash
ip route
ping -c 3 <remote-router-ip>
ssh <user>@<active-pi-ip> 'hostname; uptime'
ssh <user>@<passive-pi-ip> 'hostname; uptime'
```

If ICMP is intentionally blocked, use SSH/TCP reachability instead of relying on ping.

## Required command-line tools

The administration environment must provide:

```text
ssh
scp or sftp
rsync
git
curl
wget
tar
gzip
xz
zstd
sha256sum
sha512sum
dd
pv
awk
sed
grep
find
```

Helpful additional tools:

```text
jq
nc/ncat
traceroute
mtr
tmux or screen
```

On Debian/Ubuntu/WSL, a typical package set is:

```bash
sudo apt update
sudo apt install -y \
  openssh-client rsync git curl wget tar gzip xz-utils zstd coreutils pv \
  gawk sed grep findutils jq netcat-openbsd traceroute mtr-tiny tmux
```

## SSH keys

The laptop must have an approved SSH key that can access both existing CentOS nodes before migration and can be injected into the RAM rescue and new Debian image/configuration.

Requirements:

- private key remains only on the administration laptop or approved secure key store;
- public key may be copied into rescue/Debian `authorized_keys`;
- key-based authentication must be tested before the maintenance window;
- do not rely solely on a password that may disappear after the OS replacement.

Recommended test:

```bash
ssh -o BatchMode=yes <user>@<passive-pi-ip> true
```

## Local storage requirement

The laptop must have enough free storage for:

- one full block-level image of the passive Pi SD card;
- preferably a second full image for the other Pi;
- the approved Debian image;
- FreeSWITCH configuration exports;
- logs/test evidence;
- temporary decompression/verification overhead.

Minimum practical rule:

```text
free space >= size of both Pi SD cards + Debian image + 10 GB headroom
```

Recommended rule:

```text
free space >= 2 x combined Pi SD-card capacity
```

For example, if both Pis use 32 GB cards, aim for at least 64-80 GB free before starting.

Check with:

```bash
df -h .
```

## Backup destination

Create a dedicated local migration directory, for example:

```bash
mkdir -p ~/pios-rebuild-artifacts/{active,passive,image,test-evidence}
chmod 700 ~/pios-rebuild-artifacts
```

This directory may contain sensitive FreeSWITCH configuration and credentials. Store it on an encrypted local disk where possible and do not sync it into an unapproved cloud folder.

## Laptop power and sleep settings

During any full SD-card backup, image write or restore:

- connect the laptop to mains power;
- disable automatic sleep/hibernate;
- disable VPN idle timeout where possible;
- avoid changing Wi-Fi/Ethernet networks;
- avoid rebooting the laptop;
- preferably use `tmux` or `screen` for long-running local shell sessions.

A lost laptop/VPN session during an ordinary backup is inconvenient. A lost session while the Pi is in RAM rescue or while an image is being written can materially complicate recovery.

## Internet connection

Use a stable connection. Avoid running the destructive phase from a marginal mobile connection unless there is no alternative.

Before migration, test sustained transfer to/from the passive Pi over the VPN using a harmless file or read-only stream. The objective is to prove the VPN remains stable for longer transfers, not just interactive SSH.

## VPN considerations

Confirm before starting:

- VPN reconnect credentials are available;
- the route to the remote Pi subnet is known;
- the VPN is hosted by the router and therefore independent of both Pi nodes;
- no policy automatically disconnects the VPN after a short idle period;
- if split tunnelling is used, the Pi subnet remains routed through the VPN;
- reconnecting the VPN does not allocate a route that conflicts with the laptop's local LAN.

## Local checksum verification

The laptop is the preferred place to verify:

- official Debian source-image SHA512;
- custom golden-image SHA512;
- compressed CentOS backup SHA256;
- FreeSWITCH export SHA256.

Do not proceed with an artifact whose checksum differs from the value recorded in the project/test evidence.

## Image streaming role

The laptop may stream the already verified Debian image over SSH to the RAM rescue instead of copying the complete raw image into Pi RAM.

Conceptually:

```text
Admin laptop
  approved image
       |
       | VPN / SSH
       v
RAM rescue on passive Pi
       |
       v
whole SD device
```

This makes the laptop part of the destructive write path. Do not begin the stream unless the VPN is stable, the target disk has passed all safety gates, and the CentOS backup exists off-node.

## Rollback role

Keep the verified CentOS full-disk image immediately accessible from the laptop during the migration. If Debian has been written but the RAM rescue is still running, that backup can be streamed back to the SD card to restore the previous CentOS installation.

Do not archive the backup somewhere slow/inaccessible until the Debian node has completed its soak period.

## Repository checkout

Before the maintenance window:

```bash
git clone https://github.com/jrwroberts1976/pios-rebuild.git
cd pios-rebuild
git status
git log -1 --oneline
```

Record the exact commit used for the migration in the test evidence.

Do not execute scripts directly from an unreviewed working tree containing local modifications.

## Admin-laptop GO / NO-GO gate

Proceed only when all are true:

```text
[PASS] VPN connects reliably
[PASS] router reachable
[PASS] active Pi reachable over SSH
[PASS] passive Pi reachable over SSH
[PASS] approved SSH key works
[PASS] required CLI tools installed
[PASS] sufficient free local storage
[PASS] laptop connected to mains power
[PASS] sleep/hibernate disabled for the maintenance period
[PASS] migration repository checked out at a recorded commit
[PASS] backup/artifact directory exists and is protected
[PASS] VPN route to the site survives Pi reboot independently
```

Run `scripts/00-admin-laptop-preflight.sh` from the administration shell as the first technical check.