# PowerShell Operating Guide

## Purpose

This project can be controlled from a Windows administration laptop using PowerShell. The PowerShell scripts are the **operator-side controllers**. The Raspberry Pi itself still runs Linux, so low-level platform actions such as `kexec`, `lsblk`, `dd`, FreeSWITCH service operations and the RAM-rescue write gate remain Linux/bash scripts executed remotely.

This separation is deliberate: PowerShell handles the VPN-side workstation workflow, file transfer, checksums, evidence and remote execution, while the destructive Linux checks remain on the machine that can actually inspect the target block device.

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

The full SD-card backup helper intentionally uses `cmd.exe` output redirection so the SSH stream is written as raw bytes rather than being interpreted as PowerShell text.

## Files

```text
scripts/powershell/
├── 00-admin-laptop-preflight.ps1
├── Invoke-PiosRemoteStage.ps1
├── 02-full-sd-backup.ps1
├── Copy-PiosArtifacts.ps1
└── 05-connect-rescue.ps1
```

The existing Linux scripts remain under `scripts/` and are staged/executed on the Raspberry Pi by `Invoke-PiosRemoteStage.ps1`.

## 1. Run the Windows laptop preflight

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

## 2. Prepare the site configuration

Copy the relevant site configuration example and populate it with the actual node values. Keep production secrets out of Git.

Example local path:

```powershell
$Config = 'C:\pios-rebuild-secure\passive-site.env'
```

The PowerShell remote runner copies the config to a temporary protected path on the target Pi, invokes the selected Linux stage with `PIOS_CONFIG` pointing at it, and removes the staged config after ordinary stages.

## 3. Run the remote preflight

```powershell
pwsh .\scripts\powershell\Invoke-PiosRemoteStage.ps1 `
  -Target <user@passive-pi-ip> `
  -RemoteScript 01-preflight.sh `
  -SiteConfig $Config
```

Repeat for the active node using its own configuration.

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

Copy the resulting artifacts to the Windows workstation:

```powershell
pwsh .\scripts\powershell\Copy-PiosArtifacts.ps1 `
  -Target <user@passive-pi-ip> `
  -OutputDirectory 'C:\pios-rebuild-artifacts\passive'
```

Treat these files as sensitive.

## 5. Take a full 32 GB rollback image

Use the **confirmed whole SD-card device** reported by preflight; do not assume it is `/dev/mmcblk0` without checking.

```powershell
pwsh .\scripts\powershell\02-full-sd-backup.ps1 `
  -Target <user@passive-pi-ip> `
  -Device /dev/mmcblk0 `
  -OutputDirectory 'C:\pios-rebuild-artifacts\passive' `
  -Label passive-centos-before-debian
```

The script creates a raw `.img` file and SHA-256 sidecar on the laptop. A 32 GB card produces approximately a full-card-sized raw file, hence the 80 GB workstation recommendation when retaining both node images plus Debian and other artifacts.

## 6. Rescue readiness

```powershell
pwsh .\scripts\powershell\Invoke-PiosRemoteStage.ps1 `
  -Target <user@passive-pi-ip> `
  -RemoteScript 03-rescue-readiness.sh `
  -SiteConfig $Config
```

Do not continue if the Linux-side result is:

```text
RESCUE_READY=NO
```

## 7. Load rescue without entering it

```powershell
pwsh .\scripts\powershell\Invoke-PiosRemoteStage.ps1 `
  -Target <user@passive-pi-ip> `
  -RemoteScript 04-load-rescue.sh `
  -SiteConfig $Config
```

Loading the kexec image is not the same as executing it.

## 8. Enter the tested RAM rescue

Only after the rescue round-trip procedure has already been proven and the maintenance gate is approved:

```powershell
pwsh .\scripts\powershell\Invoke-PiosRemoteStage.ps1 `
  -Target <user@passive-pi-ip> `
  -RemoteScript 05-enter-rescue.sh `
  -SiteConfig $Config `
  -RemoteArgs ENTER_RESCUE
```

The normal SSH connection will disappear when Linux transfers control into the RAM rescue.

Reconnect:

```powershell
pwsh .\scripts\powershell\05-connect-rescue.ps1 `
  -Target <passive-pi-ip> `
  -Port 2222 `
  -User root
```

Inside rescue, re-run the required RAM-root, network, SD-device and mount checks from `RUNBOOK.md` before any write.

## 9. Debian image write

The actual SD-card write remains a **Linux rescue-side operation** by design. Do not replace the Linux safety gates with a Windows-only `dd` equivalent.

The approved `06-write-debian.sh` checks that:

- the expected Raspberry Pi hardware is present;
- the requested target matches the configured whole-disk target;
- rescue root appears RAM-resident;
- the target and child partitions are unmounted;
- the explicit `ERASE_CENTOS` confirmation is present;
- the approved image checksum is available for local-image mode.

PowerShell is the control console used to connect to rescue and initiate the already-tested rescue-side writer. The exact transfer method must match the tested release procedure in `RELEASE_DAY.md`.

## 10. Validate Debian after first boot

Once the Pi has rebooted into Debian and SSH is back on the normal management port:

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

Copy the verified export to the Debian Pi, then invoke the restore with the explicit confirmation:

```powershell
pwsh .\scripts\powershell\Invoke-PiosRemoteStage.ps1 `
  -Target <user@passive-pi-ip> `
  -RemoteScript 07a-restore-freeswitch-config.sh `
  -SiteConfig $Config `
  -RemoteArgs @('--archive','/protected/path/freeswitch-config.tgz','--confirm','APPLY_FREESWITCH_CONFIG')
```

The archive checksum sidecar must be beside the archive on the Pi.

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

If local policy blocks project scripts, do not permanently weaken the workstation security policy merely for the migration. Prefer a process-scoped invocation where permitted by your organisation, for example:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

or use your organisation's approved signing/process policy.

## Safety rule

PowerShell convenience must never remove a release gate. If a remote command, SSH session, VPN connection, checksum or device identity check behaves differently from the rehearsed procedure, stop and use the rollback/decision path in `RELEASE_DAY.md` rather than improvising.
