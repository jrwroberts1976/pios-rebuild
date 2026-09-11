# Release Day - Raspberry Pi Rebuild

## Purpose

This is the **on-the-day operator document** for rebuilding one Raspberry Pi from CentOS to Debian 13 using the already-tested RAM-rescue procedure.

Supported profiles:

| Profile | Source | Target |
| --- | --- | --- |
| `PI3-CENTOS7` | Raspberry Pi 3 / CentOS 7 | Debian 13 arm64 |
| `PI4-CENTOS9` | Raspberry Pi 4 / CentOS 9 | Debian 13 arm64 |

Do not use this document to invent or test the rescue method for the first time during production. The exact profile-specific rescue round trip and Debian image must already have been proven.

For Pi 4 / CentOS 9, also read `PI4_CENTOS9.md`.

---

## Change record

Complete before starting.

```text
Change / release reference:
Date:
Engineer:
Planned start:
Planned finish:
Site:

Migration profile: PI3-CENTOS7 / PI4-CENTOS9

Active node hostname:
Active node IP:
Active node OS/version:

Node being rebuilt:
Node role at start: PASSIVE
Node IP:
Node MAC:
Raspberry Pi model:
Current CentOS version:
SD device:
SD capacity: 32 GB

VPN router IP:
Debian image filename:
Debian image SHA512:
Rescue build/kernel/initramfs/DTB identity:
Git commit used:
Rollback image filename:
Rollback image SHA256:
FreeSWITCH export filename:
FreeSWITCH export SHA256:
```

Do not infer active/passive state from hostname alone. Confirm actual live service state.

A mismatch between **migration profile, Raspberry Pi model or current CentOS version is a NO-GO**.

---

## Expected duration

For the **first passive-node migration of a profile**, book a **3-4 hour maintenance/engineering window**.

Once that profile is proven, a subsequent Pi should normally require approximately **1.5-2.5 hours**, although a 2-3 hour working allowance remains sensible.

| Activity | Expected time |
| --- | ---: |
| Final pre-flight and role confirmation | 10-15 min |
| Final configuration/inventory export | 15-30 min |
| Full 32 GB rollback image | 20-45 min |
| Enter/validate proven RAM rescue | 10-20 min |
| Write/configure Debian | 15-30 min |
| Debian first boot and OS validation | 10-20 min |
| FreeSWITCH restore/reconciliation | 20-40 min |
| FreeSWITCH and functional validation | 20-40 min |
| Contingency/decision allowance | 30-60 min |

The scheduled soak period is **not** part of the hands-on migration window.

---

# RELEASE GATE -1 - Set up PowerShell and Git

Do this before the maintenance window starts.

If the repository has not been cloned:

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
```

Then record the exact release version:

```powershell
git status
git log -1 --oneline
$ReleaseCommit = (git rev-parse HEAD).Trim()
Write-Host "Release commit: $ReleaseCommit"
```

Or use:

```powershell
pwsh .\scripts\powershell\00-setup-environment.ps1 `
  -RepoPath $RepoPath `
  -Branch main
```

Required result:

```text
ENVIRONMENT_SETUP=PASS
```

After the release commit is recorded, **do not run `git pull` again during the change**.

```text
[ ] Working tree clean
[ ] git fetch origin --prune completed
[ ] main checked out
[ ] git pull --ff-only origin main completed
[ ] Exact commit SHA recorded
[ ] No further Git updates during this change
```

---

# RELEASE GATE 0 - Select and verify migration profile

For Pi 3 / CentOS 7 use the Pi 3 profile configuration. For Pi 4 / CentOS 9 use:

```text
config/site-pi4-centos9.env.example
```

The populated production config must remain outside Git or otherwise protected.

Confirm:

```text
[ ] Migration profile selected
[ ] Raspberry Pi model matches profile
[ ] Current CentOS version matches profile
[ ] Correct profile-specific rescue build has already passed round-trip testing
[ ] Exact Debian image has been boot-tested on this Pi hardware family
```

For `PI4-CENTOS9`, required source identity is Raspberry Pi 4 + CentOS 9. A Pi 3 rescue validation does not count.

---

# RELEASE GATE 1 - Before the change window

All items below must already be true:

```text
[ ] Debian image built and checksum recorded
[ ] Exact Debian image boot-tested on representative target hardware
[ ] FreeSWITCH on Debian test completed
[ ] Required FreeSWITCH modules identified
[ ] Profile-specific RAM-rescue build tested
[ ] Current CentOS -> RAM rescue -> same CentOS round trip proven on passive node
[ ] VPN confirmed to terminate on router, not either Pi
[ ] SSH key access confirmed to both nodes
[ ] Laptop connected to mains power
[ ] Laptop sleep/hibernate disabled
[ ] At least 80 GB local free space when retaining both 32 GB card images
[ ] Repository commit pinned
[ ] Rollback procedure understood
```

**NO-GO:** if any mandatory item is unresolved, postpone the destructive change.

---

# RELEASE GATE 2 - Start-of-change validation

Connect the VPN and run:

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

Then verify:

```text
[ ] Active node healthy and carrying service
[ ] Passive node healthy and not required for current production traffic
[ ] Both nodes reachable over VPN/SSH
[ ] No unrelated site/network incident in progress
[ ] Correct node selected for rebuild
```

Record actual start time and GO/NO-GO decision.

---

# RELEASE GATE 3 - Final node/profile preflight

Run:

```powershell
pwsh .\scripts\powershell\Invoke-PiosRemoteStage.ps1 `
  -Target <user@passive-pi-ip> `
  -RemoteScript 01-preflight.sh `
  -SiteConfig <secure-site-config-path>
```

Required profile checks must pass:

```text
[ ] Pi model matches EXPECTED_MODEL_REGEX
[ ] Architecture matches EXPECTED_ARCH
[ ] CentOS ID matches EXPECTED_SOURCE_OS_ID
[ ] CentOS version matches EXPECTED_SOURCE_OS_VERSION
[ ] Whole target device confirmed
[ ] Expected network interface/default route present
```

For Pi 4 / CentOS 9 this must explicitly prove Pi 4 and CentOS 9.

---

# RELEASE GATE 4 - Final inventory and FreeSWITCH export

Run:

```powershell
pwsh .\scripts\powershell\Invoke-PiosRemoteStage.ps1 `
  -Target <user@passive-pi-ip> `
  -RemoteScript 02-backup-inventory.sh `
  -SiteConfig <secure-site-config-path>

pwsh .\scripts\powershell\Invoke-PiosRemoteStage.ps1 `
  -Target <user@passive-pi-ip> `
  -RemoteScript 02a-export-freeswitch-config.sh `
  -SiteConfig <secure-site-config-path>

pwsh .\scripts\powershell\Copy-PiosArtifacts.ps1 `
  -Target <user@passive-pi-ip> `
  -OutputDirectory 'C:\pios-rebuild-artifacts\passive'
```

Verify:

```text
[ ] Final inventory copied off-node
[ ] FreeSWITCH export copied off-node
[ ] FreeSWITCH export checksum verified
```

**NO-GO:** do not overwrite the SD card without the FreeSWITCH export safely off-node.

---

# RELEASE GATE 5 - Full 32 GB rollback image

Use the **confirmed whole-card device** from preflight:

```powershell
pwsh .\scripts\powershell\02-full-sd-backup.ps1 `
  -Target <user@passive-pi-ip> `
  -Device <confirmed-whole-card-device> `
  -OutputDirectory 'C:\pios-rebuild-artifacts\passive' `
  -Label passive-centos-before-debian
```

Record rollback image path, bytes, SHA-256 and completion time.

Required:

```text
[ ] Backup completed successfully
[ ] Raw image has expected full-card size
[ ] SHA256 sidecar exists
[ ] Image is on approved off-node storage
```

**NO-GO:** if the image is incomplete, unexpectedly small or unavailable, stop.

---

# RELEASE GATE 6 - RAM-rescue readiness and load

Run:

```powershell
pwsh .\scripts\powershell\Invoke-PiosRemoteStage.ps1 `
  -Target <user@passive-pi-ip> `
  -RemoteScript 03-rescue-readiness.sh `
  -SiteConfig <secure-site-config-path>
```

Required result:

```text
RESCUE_READY=YES
```

For Pi 4 / CentOS 9, confirm the rescue kernel/initramfs/DTB/cmdline combination is the exact Pi 4 profile that passed the non-destructive test.

Load it without executing:

```powershell
pwsh .\scripts\powershell\Invoke-PiosRemoteStage.ps1 `
  -Target <user@passive-pi-ip> `
  -RemoteScript 04-load-rescue.sh `
  -SiteConfig <secure-site-config-path>
```

---

# RELEASE GATE 7 - Enter RAM rescue

Final checks:

```text
[ ] Active CentOS node still healthy
[ ] VPN stable
[ ] Full rollback image available + checksummed
[ ] FreeSWITCH export available + checksummed
[ ] Correct passive Pi selected
[ ] Profile-specific rescue previously round-trip tested
```

Enter rescue:

```powershell
pwsh .\scripts\powershell\Invoke-PiosRemoteStage.ps1 `
  -Target <user@passive-pi-ip> `
  -RemoteScript 05-enter-rescue.sh `
  -SiteConfig <secure-site-config-path> `
  -RemoteArgs ENTER_RESCUE
```

Reconnect:

```powershell
pwsh .\scripts\powershell\05-connect-rescue.ps1 `
  -Target <passive-pi-ip> `
  -Port 2222 `
  -User root
```

Inside rescue verify:

```bash
findmnt /
ip -br addr
ip route
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL
fdisk -l <confirmed-whole-card-device>
```

Required:

```text
[ ] Rescue root is RAM/initramfs
[ ] Expected wired network works
[ ] Default route present
[ ] VPN path reaches rescue SSH
[ ] Correct 32 GB SD card visible
[ ] Target and child partitions unmounted
```

**STOP:** if rescue validation fails, do not write Debian.

---

# RELEASE GATE 8 - Destructive Debian write

This is the point of destructive change.

Before proceeding confirm and record:

```text
PROFILE: <PI3-CENTOS7 / PI4-CENTOS9>
NODE: <passive hostname/IP>
ROLE: PASSIVE
PI MODEL: <confirmed model>
SOURCE OS: <confirmed CentOS version>
TARGET DISK: <confirmed whole SD device>
ROLLBACK IMAGE: AVAILABLE + CHECKSUMMED
DEBIAN IMAGE: APPROVED + CHECKSUM MATCHES
ACTIVE NODE: HEALTHY
```

Use the already-tested Linux rescue-side writer:

```bash
bash /path/to/06-write-debian.sh \
  --target <confirmed-whole-card-device> \
  --image /path/to/approved-debian.img.xz \
  --confirm ERASE_CENTOS
```

Required result:

```text
DEBIAN_IMAGE_WRITE_COMPLETE=YES
```

Do not bypass the RAM-root, unmounted-target, model or checksum gates.

After the write, do not reboot immediately. Apply only the tested node-specific hostname/network/SSH configuration and inspect the new filesystems first.

---

# RELEASE GATE 9 - First Debian boot

Reboot only after offline checks pass. Wait for normal SSH to return through the router VPN.

Run:

```powershell
pwsh .\scripts\powershell\Invoke-PiosRemoteStage.ps1 `
  -Target <user@passive-pi-ip> `
  -RemoteScript 07-validate-debian.sh `
  -SiteConfig <secure-site-config-path>
```

Required result:

```text
DEBIAN_VALIDATION=PASS
```

Also verify hostname, IP/MAC/interface, gateway, DNS, SSH key access, time, systemd health and storage layout.

---

# RELEASE GATE 10 - FreeSWITCH restore and smoke test

Confirm required Debian FreeSWITCH packages/modules are present. Copy the verified FreeSWITCH export and checksum sidecar to Debian.

Run the restore and then smoke test:

```powershell
pwsh .\scripts\powershell\Invoke-PiosRemoteStage.ps1 `
  -Target <user@passive-pi-ip> `
  -RemoteScript 07a-restore-freeswitch-config.sh `
  -SiteConfig <secure-site-config-path> `
  -RemoteArgs @('--archive','/protected/path/freeswitch-config.tgz','--confirm','APPLY_FREESWITCH_CONFIG')

pwsh .\scripts\powershell\Invoke-PiosRemoteStage.ps1 `
  -Target <user@passive-pi-ip> `
  -RemoteScript 08-freeswitch-smoke-test.sh `
  -SiteConfig <secure-site-config-path> `
  -RemoteArgs '--start'
```

Required:

```text
FREESWITCH_SMOKE_TEST=PASS
```

Complete the functional test plan: required modules, Sofia profiles, gateways/trunks, registrations, inbound/outbound calls, two-way RTP/audio, DTMF, codecs, caller ID, logging/monitoring and reboot persistence.

Do not fail production service over merely because the FreeSWITCH process starts.

---

# RELEASE GATE 11 - End-of-day decision

Normal successful end state for the first passive migration:

```text
ACTIVE NODE: original CentOS node still carrying production
PASSIVE NODE: Debian rebuilt and validated
NEXT STEP: 24-48 hour passive soak
```

Record:

```text
Migration technical result: PASS / FAIL / ROLLED BACK
Debian validation: PASS / FAIL
FreeSWITCH smoke test: PASS / FAIL
Functional test result: PASS / FAIL
Actual finish time:
Issues / defects raised:
Engineer decision:
```

Do not rebuild the active CentOS node on the same day merely because the first rebuild finished early.

---

# Rollback decision matrix

| Point reached | Action |
| --- | --- |
| Before entering rescue | Stop change; no OS rollback required |
| Rescue running, SD untouched | Reboot back to original CentOS |
| Debian write started/finished but rescue alive | Restore verified full CentOS image to same confirmed SD device |
| Debian boots but validation fails | Keep active CentOS node serving production; repair/rebuild passive |
| FreeSWITCH restore/testing fails | Keep active CentOS serving; restore clean Debian config or rebuild passive |
| Later production failover fails | Fail service back to untouched CentOS node |

A rollback is a successful controlled outcome when a release gate fails.

---

# Absolute stop conditions

Stop rather than improvise if:

```text
- migration profile does not match Pi model/source CentOS version
- VPN/router connectivity becomes unreliable
- active/passive role cannot be proved
- active production node becomes unhealthy
- target disk identity is uncertain
- rollback image is missing or suspect
- FreeSWITCH export is missing or suspect
- profile-specific rescue readiness/round-trip has not passed
- rescue cannot be reached over VPN
- rescue root is not demonstrably RAM-resident
- target card or child partition remains mounted
- Debian image checksum does not match approved artifact
- unexpected hardware/boot layout is observed
- unresolved Severity 1/2 FreeSWITCH defect exists
```

---

# Separate production failover release

After the rebuilt Debian passive node has completed its **24-48 hour passive soak**, schedule a separate controlled production failover window of approximately **1-2 hours**.

At that release, confirm both nodes healthy, refresh any configuration export that may have changed, move service to Debian, test critical telephony paths immediately, return service to CentOS if acceptance fails, and keep the former CentOS active node unchanged during the production soak.

Only after production soak approval should the second node be rebuilt.

This deliberately separates **OS migration risk** from **production failover risk**.

For a possible future one-command path, see `../higher-risk-fully-automated-script.md`. That design is intentionally classified as higher risk and does not replace this release-day process.
