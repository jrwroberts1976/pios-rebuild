# Admin Laptop Prerequisites

## Purpose

The remote rebuild depends on the engineer's laptop remaining a reliable control point throughout backup, RAM-rescue, image streaming, validation and rollback. The laptop therefore has its own formal prerequisite gate before either Raspberry Pi is touched.

## Supported working environment

Supported:

- Windows using PowerShell/PowerShell 7 and the scripts under `scripts/powershell/`;
- Windows using WSL2 with an Ubuntu/Debian environment;
- Linux laptop; or
- macOS with equivalent command-line tools installed.

For the planned Windows workflow, **PowerShell 7 is preferred** and the operating sequence is documented in `POWERSHELL.md`.

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

Linux/WSL examples:

```bash
ip route
ping -c 3 <remote-router-ip>
ssh <user>@<active-pi-ip> 'hostname; uptime'
ssh <user>@<passive-pi-ip> 'hostname; uptime'
```

PowerShell examples:

```powershell
Test-Connection <remote-router-ip> -Count 3
ssh <user>@<active-pi-ip> 'hostname; uptime'
ssh <user>@<passive-pi-ip> 'hostname; uptime'
```

If ICMP is intentionally blocked, use SSH/TCP reachability instead of relying on ping.

## Required command-line tools

For Windows PowerShell:

```text
ssh.exe
scp.exe
git.exe
PowerShell 7 preferred
```

Optional but useful on Windows:

```text
xz.exe
zstd.exe
7z.exe
wsl.exe
tracert.exe
```

The PowerShell full-card backup helper uses `cmd.exe` redirection to preserve the SSH stream as raw bytes.

For Linux/WSL/macOS administration environments the toolset remains:

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

Helpful additional Linux/WSL tools:

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

Recommended Linux/WSL test:

```bash
ssh -o BatchMode=yes <user>@<passive-pi-ip> true
```

The PowerShell preflight performs the equivalent BatchMode test automatically.

## Local storage requirement

Both Raspberry Pis use **32 GB SD cards**.

If retaining a full raw rollback image of both cards on the administration laptop, allow approximately 32 GB per card plus working space for:

- the approved Debian image;
- FreeSWITCH configuration exports;
- logs/test evidence;
- checksums;
- temporary files.

For this project use:

```text
70 GB free = practical minimum
80 GB free = recommended release-day minimum
```

The standard PowerShell preflight therefore defaults to an **80 GB** requirement.

PowerShell check:

```powershell
Get-PSDrive -PSProvider FileSystem
```

Linux/WSL check:

```bash
df -h .
```

## Backup destination

Create a dedicated local migration directory.

PowerShell example:

```powershell
New-Item -ItemType Directory -Force 'C:\pios-rebuild-artifacts\active'
New-Item -ItemType Directory -Force 'C:\pios-rebuild-artifacts\passive'
New-Item -ItemType Directory -Force 'C:\pios-rebuild-artifacts\image'
New-Item -ItemType Directory -Force 'C:\pios-rebuild-artifacts\test-evidence'
```

Linux/WSL example:

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
- keep the PowerShell/terminal session available for the complete operation.

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
- CentOS full-card backup SHA256;
- FreeSWITCH export SHA256.

On Windows, use `Get-FileHash` where appropriate. Do not proceed with an artifact whose checksum differs from the value recorded in the project/test evidence.

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

The tested Linux rescue-side writer remains the authoritative safety gate for the destructive operation; PowerShell does not replace its block-device, mount-state or RAM-root checks.

## Rollback role

Keep the verified CentOS full-disk image immediately accessible from the laptop during the migration. If Debian has been written but the RAM rescue is still running, that backup can be streamed back to the SD card to restore the previous CentOS installation.

Do not archive the backup somewhere slow/inaccessible until the Debian node has completed its soak period.

## Repository checkout

PowerShell example:

```powershell
git clone https://github.com/jrwroberts1976/pios-rebuild.git
Set-Location pios-rebuild
git status
git log -1 --oneline
```

Linux/WSL equivalent:

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
[PASS] at least 80 GB free for the two-card rollback workflow
[PASS] laptop connected to mains power
[PASS] sleep/hibernate disabled for the maintenance period
[PASS] migration repository checked out at a recorded commit
[PASS] backup/artifact directory exists and is protected
[PASS] VPN route to the site survives Pi reboot independently
```

Windows PowerShell release-day preflight:

```powershell
pwsh .\scripts\powershell\00-admin-laptop-preflight.ps1 `
  -Router <router-ip> `
  -Active <user@active-pi-ip> `
  -Passive <user@passive-pi-ip> `
  -MinFreeGB 80
```

Linux/WSL equivalent:

```bash
./scripts/00-admin-laptop-preflight.sh \
  --router <router-ip> \
  --active <user@active-pi-ip> \
  --passive <user@passive-pi-ip> \
  --min-free-gb 80
```

Use `RELEASE_DAY.md` as the operator checklist during the actual change window.
