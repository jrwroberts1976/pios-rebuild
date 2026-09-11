# Admin Laptop Prerequisites

## Purpose

The remote rebuild depends on the engineer's laptop remaining a reliable control point throughout backup, RAM-rescue, image streaming, validation and rollback. The laptop therefore has its own formal prerequisite gate before either Raspberry Pi is touched.

The project supports both **Raspberry Pi 3 / CentOS 7** and **Raspberry Pi 4 / CentOS 9** source profiles. The laptop requirements are common to both; the node configuration and rescue build must match the selected profile.

## Supported working environment

Supported:

- Windows using PowerShell/PowerShell 7 and the scripts under `scripts/powershell/`;
- Windows using WSL2 with an Ubuntu/Debian environment;
- Linux laptop; or
- macOS with equivalent command-line tools installed.

For the planned Windows workflow, **PowerShell 7 is preferred** and the operating sequence is documented in `POWERSHELL.md`.

The VPN client itself may run natively on Windows/macOS. The key requirement is that the shell used for migration can reach both Pi nodes through the established router-hosted VPN.

## Required network access

Before starting, the laptop must be able to establish the site VPN reliably, reach the remote router, reach both Raspberry Pi management IPs, SSH to both CentOS nodes, later SSH to the RAM-rescue port (default TCP/2222), later SSH to Debian on TCP/22, download approved packages where required and maintain the VPN route while one Pi reboots.

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

## SSH keys

The laptop must have an approved SSH key that can access both existing CentOS nodes before migration and can be injected into RAM rescue and the new Debian configuration.

The private key remains only on the administration laptop or approved secure key store; the public key may be copied into rescue/Debian `authorized_keys`; key authentication must be tested before the maintenance window; and the migration must not rely solely on a password that may disappear after OS replacement.

## Local storage requirement

Both Raspberry Pi estates use **32 GB SD cards**.

If retaining a full raw rollback image of both cards on the administration laptop, allow approximately 32 GB per card plus working space for the approved Debian image, FreeSWITCH exports, logs/evidence, checksums and temporary files.

For this project use:

```text
70 GB free = practical minimum
80 GB free = recommended release-day minimum
```

The PowerShell preflight therefore defaults to **80 GB** for the two-card workflow.

PowerShell check:

```powershell
Get-PSDrive -PSProvider FileSystem
```

## Backup destination

Create a dedicated local migration directory, for example:

```powershell
New-Item -ItemType Directory -Force 'C:\pios-rebuild-artifacts\active'
New-Item -ItemType Directory -Force 'C:\pios-rebuild-artifacts\passive'
New-Item -ItemType Directory -Force 'C:\pios-rebuild-artifacts\image'
New-Item -ItemType Directory -Force 'C:\pios-rebuild-artifacts\test-evidence'
```

This directory may contain sensitive FreeSWITCH configuration and credentials. Store it on encrypted local storage where practical and do not sync it to an unapproved cloud folder.

## Laptop power and sleep settings

During any full SD-card backup, image write or restore:

- connect the laptop to mains power;
- disable automatic sleep/hibernate;
- disable VPN idle timeout where possible;
- avoid changing Wi-Fi/Ethernet networks;
- avoid rebooting the laptop;
- keep the PowerShell/terminal session available for the complete operation.

## Internet and VPN considerations

Use a stable connection. Before migration, test sustained transfer to/from the passive Pi over the VPN using a harmless file or read-only stream.

Confirm VPN reconnect credentials are available, the route to the remote Pi subnet is known, the VPN is hosted by the router and independent of both Pi nodes, split-tunnel routing is correct, and reconnecting does not create a route conflict with the laptop's local LAN.

## Local checksum verification

The laptop is the preferred place to verify the official Debian source-image SHA512, custom golden-image SHA512, CentOS full-card backup SHA256 and FreeSWITCH export SHA256. On Windows, use `Get-FileHash` where appropriate.

Do not proceed with an artifact whose checksum differs from the value recorded in project/test evidence.

## Migration profile selection

Before running node-side preflight, select the correct source profile:

```text
PI3-CENTOS7 -> config/site.env.example
PI4-CENTOS9 -> config/site-pi4-centos9.env.example
```

Copy the selected example to protected storage and populate the actual values. A Pi 4 / CentOS 9 run must retain the Pi 4 model and CentOS 9 source-OS gates. Do not loosen them simply to make a preflight succeed.

The Pi 4 / CentOS 9 rescue build is a separate tested artifact from any Pi 3 / CentOS 7 rescue build.

## Image streaming role

The laptop may stream the already verified Debian image over SSH to RAM rescue instead of copying the complete raw image into Pi RAM. The Linux rescue-side writer remains the authoritative safety gate and directly verifies the target block device, mount state and RAM-root state.

## Rollback role

Keep the verified full-card image immediately accessible from the laptop during migration. If Debian has been written but RAM rescue is still running, that backup can be streamed back to the same confirmed SD device to restore the previous CentOS installation.

Do not archive the backup somewhere slow/inaccessible until the Debian node has completed its soak period.

## Repository checkout

Before the maintenance window:

```powershell
$RepoPath = Join-Path $HOME 'pios-rebuild'
git clone https://github.com/jrwroberts1976/pios-rebuild.git $RepoPath
Set-Location $RepoPath
```

For an existing checkout:

```powershell
git status --short
git fetch origin --prune
git checkout main
git pull --ff-only origin main
git log -1 --oneline
$ReleaseCommit = (git rev-parse HEAD).Trim()
```

Record the exact commit and do not pull again during the release.

## Admin-laptop GO / NO-GO gate

Proceed only when all are true:

```text
[PASS] correct migration profile selected
[PASS] VPN connects reliably
[PASS] router reachable
[PASS] active Pi reachable over SSH
[PASS] passive Pi reachable over SSH
[PASS] approved SSH key works
[PASS] required CLI tools installed
[PASS] at least 80 GB free for the two-card rollback workflow
[PASS] laptop connected to mains power
[PASS] sleep/hibernate disabled
[PASS] exact Git release commit recorded
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

Use `RELEASE_DAY.md` as the operator checklist during the actual change window.
