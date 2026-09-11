# PowerShell Operating Guide

## Purpose

This project can be controlled from a Windows administration laptop using PowerShell. The PowerShell scripts are the **operator-side controllers**. The Raspberry Pi still runs Linux, so low-level actions such as `kexec`, `lsblk`, `dd`, FreeSWITCH service operations and the RAM-rescue write gate remain Linux/bash scripts executed remotely.

Supported migration profiles are:

| Profile | Source | Target |
| --- | --- | --- |
| `PI3-CENTOS7` | Raspberry Pi 3 / CentOS 7 | Debian 13 arm64 |
| `PI4-CENTOS9` | Raspberry Pi 4 / CentOS 9 | Debian 13 arm64 |

For Pi 4 / CentOS 9, read `PI4_CENTOS9.md` before release execution. The rescue environment must be separately proven for Pi 4 / CentOS 9 and must not be assumed compatible because the Pi 3 process works.

## Requirements

Recommended workstation:

- Windows 11 or supported Windows 10;
- PowerShell 7 preferred;
- OpenSSH Client (`ssh.exe` and `scp.exe`);
- Git for Windows;
- at least **80 GB free** when retaining raw rollback images of both 32 GB SD cards;
- VPN connected to the remote router/site;
- SSH key access to both Raspberry Pis;
- laptop connected to mains power with sleep/hibernate disabled for the maintenance window.

The full SD-card backup helper intentionally uses binary-safe command redirection so the SSH stream is written as raw bytes rather than interpreted as PowerShell text.

## Files

```text
scripts/powershell/
├── 00-setup-environment.ps1
├── 00-admin-laptop-preflight.ps1
├── Invoke-PiosRemoteStage.ps1
├── 02-full-sd-backup.ps1
├── Copy-PiosArtifacts.ps1
└── 05-connect-rescue.ps1
```

The existing Linux scripts remain under `scripts/` and are staged/executed on the Raspberry Pi by `Invoke-PiosRemoteStage.ps1`.

## 0. Set up or refresh the Git environment

Do this **before the maintenance/change window starts**. Once the exact release commit has been recorded, do not run another `git pull` during the migration.

If the repository is not already on the laptop:

```powershell
$RepoPath = Join-Path $HOME 'pios-rebuild'
git clone https://github.com/jrwroberts1976/pios-rebuild.git $RepoPath
Set-Location $RepoPath
```

If it already exists:

```powershell
$RepoPath = Join-Path $HOME 'pios-rebuild'
Set-Location $RepoPath
git status --short
git fetch origin --prune
git checkout main
git pull --ff-only origin main
git status
git log -1 --oneline
$ReleaseCommit = (git rev-parse HEAD).Trim()
Write-Host "Release commit: $ReleaseCommit"
```

The working tree must be clean before the pull. `git pull --ff-only` is intentional: if the local branch has diverged, stop rather than creating an unreviewed merge.

The same preparation can be performed with:

```powershell
pwsh .\scripts\powershell\00-setup-environment.ps1 `
  -RepoPath $RepoPath `
  -Branch main
```

Required result:

```text
ENVIRONMENT_SETUP=PASS
```

Record the full commit SHA in the release record. From this point, do not update the repository again during the change.

## 1. Select the migration profile

For Raspberry Pi 3 / CentOS 7, start from:

```text
config/site.env.example
```

For Raspberry Pi 4 / CentOS 9, start from:

```text
config/site-pi4-centos9.env.example
```

Copy the matching file to protected local storage and populate the actual node-specific values. Do not commit the populated configuration.

Example:

```powershell
$Config = 'C:\pios-rebuild-secure\passive-site.env'
```

The Pi 4 profile contains fail-closed values similar to:

```text
EXPECTED_MODEL_REGEX='^Raspberry Pi 4'
EXPECTED_SOURCE_OS_ID='centos'
EXPECTED_SOURCE_OS_VERSION='9'
```

A profile mismatch is a NO-GO. Do not loosen those values just to make the preflight pass.

## 2. Run the Windows laptop preflight

From the repository root:

```powershell
pwsh .\scripts\powershell\00-admin-laptop-preflight.ps1 `
  -Router <router-ip> `
  -Active <user@active-pi-ip> `
  -Passive <user@passive-pi-ip> `
  -MinFreeGB 80
```

Required result:

```text
ADMIN_LAPTOP_PREFLIGHT=PASS
```

## 3. Run the remote preflight

```powershell
pwsh .\scripts\powershell\Invoke-PiosRemoteStage.ps1 `
  -Target <user@passive-pi-ip> `
  -RemoteScript 01-preflight.sh `
  -SiteConfig $Config
```

Repeat for the active node using its own configuration. The Linux-side preflight now checks the configured Pi model, architecture and expected source CentOS ID/version.

For Pi 4 / CentOS 9, required evidence includes the exact Pi 4 model string, CentOS 9 identity, running kernel, boot files, kexec support, Ethernet and target SD-card layout.

## 4. Capture inventory and FreeSWITCH configuration

```powershell
pwsh .\scripts\powershell\Invoke-PiosRemoteStage.ps1 `
  -Target <user@passive-pi-ip> `
  -RemoteScript 02-backup-inventory.sh `
  -SiteConfig $Config

pwsh .\scripts\powershell\Invoke-PiosRemoteStage.ps1 `
  -Target <user@passive-pi-ip> `
  -RemoteScript 02a-export-freeswitch-config.sh `
  -SiteConfig $Config
```

Copy the artifacts to the Windows workstation:

```powershell
pwsh .\scripts\powershell\Copy-PiosArtifacts.ps1 `
  -Target <user@passive-pi-ip> `
  -OutputDirectory 'C:\pios-rebuild-artifacts\passive'
```

Treat these files as sensitive and verify their checksums.

## 5. Take a full 32 GB rollback image

Use the **confirmed whole SD-card device** reported by preflight; do not assume it is `/dev/mmcblk0` without checking.

```powershell
pwsh .\scripts\powershell\02-full-sd-backup.ps1 `
  -Target <user@passive-pi-ip> `
  -Device <confirmed-whole-card-device> `
  -OutputDirectory 'C:\pios-rebuild-artifacts\passive' `
  -Label passive-centos-before-debian
```

A 32 GB card produces approximately a full-card-sized raw file, hence the 80 GB recommendation when retaining both node images plus Debian and other artifacts.

## 6. Rescue readiness

```powershell
pwsh .\scripts\powershell\Invoke-PiosRemoteStage.ps1 `
  -Target <user@passive-pi-ip> `
  -RemoteScript 03-rescue-readiness.sh `
  -SiteConfig $Config
```

Do not continue if the Linux-side result is `RESCUE_READY=NO`.

For Pi 4 / CentOS 9, the rescue kernel/initramfs/DTB values in `$Config` must refer to the **Pi 4 / CentOS 9 rescue build that already passed a non-destructive round trip**.

## 7. Load rescue without entering it

```powershell
pwsh .\scripts\powershell\Invoke-PiosRemoteStage.ps1 `
  -Target <user@passive-pi-ip> `
  -RemoteScript 04-load-rescue.sh `
  -SiteConfig $Config
```

Loading the kexec image is not the same as executing it.

## 8. Enter the tested RAM rescue

Only after the profile-specific rescue round trip has already been proven:

```powershell
pwsh .\scripts\powershell\Invoke-PiosRemoteStage.ps1 `
  -Target <user@passive-pi-ip> `
  -RemoteScript 05-enter-rescue.sh `
  -SiteConfig $Config `
  -RemoteArgs ENTER_RESCUE
```

Reconnect:

```powershell
pwsh .\scripts\powershell\05-connect-rescue.ps1 `
  -Target <passive-pi-ip> `
  -Port 2222 `
  -User root
```

Inside rescue, re-run the RAM-root, network, SD-device and mount checks from `RUNBOOK.md` before any write.

## 9. Debian image write

The actual SD-card write remains a **Linux rescue-side operation** by design. Do not replace the Linux safety gates with a Windows-only writer.

The approved `06-write-debian.sh` checks expected hardware, configured whole-disk target, RAM-resident rescue root, unmounted target/children, explicit `ERASE_CENTOS` confirmation and the approved image checksum where applicable.

PowerShell is the control console used to connect to rescue and initiate the already-tested rescue-side writer. The exact transfer method must match `RELEASE_DAY.md`.

## 10. Validate Debian after first boot

```powershell
pwsh .\scripts\powershell\Invoke-PiosRemoteStage.ps1 `
  -Target <user@passive-pi-ip> `
  -RemoteScript 07-validate-debian.sh `
  -SiteConfig $Config
```

Required result:

```text
DEBIAN_VALIDATION=PASS
```

## 11. Restore FreeSWITCH configuration

Copy the verified export and checksum sidecar to the rebuilt Pi, then invoke the restore with the explicit confirmation:

```powershell
pwsh .\scripts\powershell\Invoke-PiosRemoteStage.ps1 `
  -Target <user@passive-pi-ip> `
  -RemoteScript 07a-restore-freeswitch-config.sh `
  -SiteConfig $Config `
  -RemoteArgs @('--archive','/protected/path/freeswitch-config.tgz','--confirm','APPLY_FREESWITCH_CONFIG')
```

## 12. FreeSWITCH smoke test

```powershell
pwsh .\scripts\powershell\Invoke-PiosRemoteStage.ps1 `
  -Target <user@passive-pi-ip> `
  -RemoteScript 08-freeswitch-smoke-test.sh `
  -SiteConfig $Config `
  -RemoteArgs '--start'
```

A smoke-test pass is not the full telephony acceptance. Complete `FREESWITCH_TEST_PLAN.md` before production failover.

## PowerShell execution policy

If local policy blocks project scripts, do not permanently weaken workstation security policy merely for the migration. Prefer a process-scoped invocation where permitted by your organisation, for example:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

or use your organisation's approved signing/process policy.

## Safety rule

PowerShell convenience must never remove a release gate. If a profile, remote command, SSH session, VPN connection, checksum, rescue build or device identity check behaves differently from the rehearsed procedure, stop and use the decision path in `RELEASE_DAY.md` rather than improvising.

For a possible future one-command orchestrator, see the root document `higher-risk-fully-automated-script.md`. It is deliberately treated as a higher-risk design and is not the default production method.
