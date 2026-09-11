# Secure node configuration for release day

This document expands the `RELEASE_DAY.md` instruction to copy the migration profile template to protected storage outside the Git repository before filling in real node values.

## Why the real configuration stays outside Git

The checked-in files under `config/` are templates only. They are intended to contain generic example values that are safe to publish. A completed node configuration can contain real infrastructure information and, depending on the site, credentials or references to sensitive material. That can include hostnames, IP addresses, SIP or gateway credentials, TLS/private-key paths, API tokens, rescue paths, image checksums and other production-specific values.

Do not edit the checked-in `.env.example` file with production values. Do not save the populated copy anywhere under the `pios-rebuild` repository. Removing a secret from a later commit does not remove it from Git history.

## Create the protected copies

From the repository root, for a Pi 4 / CentOS 9 site:

```powershell
$SecurePath = 'C:\pios-rebuild-secure'

New-Item -ItemType Directory `
  -Path $SecurePath `
  -Force | Out-Null

Copy-Item `
  '.\config\site-pi4-centos9.env.example' `
  "$SecurePath\passive-site.env"

Copy-Item `
  '.\config\site-pi4-centos9.env.example' `
  "$SecurePath\active-site.env"
```

The intended layout is:

```text
C:\Users\<engineer>\pios-rebuild\
└── config\
    └── site-pi4-centos9.env.example   <-- generic template; safe to keep in Git

C:\pios-rebuild-secure\
├── passive-site.env                   <-- real passive-node values; never commit
└── active-site.env                    <-- real active-node values; never commit
```

Create one node-specific file per Pi. The passive file must describe the passive Pi being rebuilt. The active file must describe the active peer.

## Populate the real node values

Edit the copies under `C:\pios-rebuild-secure\` and replace the example values with the real values for each node. Use the exact variable names from the checked-in template; do not invent or rename variables on release day to make a check pass.

The values can include the migration profile, expected Pi model, architecture, source OS version, hostname/IP information, network interface, confirmed whole SD-card device, RAM-rescue paths and port, and approved Debian image checksum.

Example shape:

```text
MIGRATION_PROFILE='PI4-CENTOS9'

EXPECTED_MODEL_REGEX='^Raspberry Pi 4'
EXPECTED_ARCH='aarch64'
EXPECTED_SOURCE_OS_ID='centos'
EXPECTED_SOURCE_OS_VERSION='9'

TARGET_HOST='<real-passive-node-address>'
TARGET_HOSTNAME='<real-passive-hostname>'
TARGET_DISK='/dev/mmcblk0'
NETWORK_INTERFACE='eth0'

RESCUE_SSH_PORT='2222'
RESCUE_KERNEL='<approved-pi4-rescue-kernel-path>'
RESCUE_INITRAMFS='<approved-pi4-rescue-initramfs-path>'
RESCUE_DTB='<approved-pi4-rescue-dtb-path>'

DEBIAN_IMAGE_SHA512='<approved-image-sha512>'
```

The exact values and names must be taken from the approved profile template and pre-flight evidence.

## Restrict the local directory

Where practical, keep the secure directory on encrypted local storage and restrict its permissions. On Windows:

```powershell
$SecurePath = 'C:\pios-rebuild-secure'

icacls $SecurePath /inheritance:r
icacls $SecurePath /grant:r "$env:USERNAME:(OI)(CI)F"
icacls $SecurePath
```

## Verify the files are outside the repository

Before continuing:

```powershell
$RepoPath = (Resolve-Path '.').Path
$PassiveConfig = 'C:\pios-rebuild-secure\passive-site.env'
$ActiveConfig  = 'C:\pios-rebuild-secure\active-site.env'

Write-Host "Repository:     $RepoPath"
Write-Host "Passive config: $PassiveConfig"
Write-Host "Active config:  $ActiveConfig"

git status --short
```

`git status --short` must not show either populated `.env` file.

## Use the protected file during the release

Reference the protected file by its full path:

```powershell
$Config = 'C:\pios-rebuild-secure\passive-site.env'

pwsh .\scripts\powershell\Invoke-PiosRemoteStage.ps1 `
  -Target <user@passive-pi-ip> `
  -RemoteScript 01-preflight.sh `
  -SiteConfig $Config
```

## NO-GO condition

If a populated production configuration has been created inside the repository, appears in `git status`, or has already been committed or pushed, stop the release and treat it as a potential credentials/information exposure before continuing.
