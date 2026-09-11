# Release Day - Raspberry Pi Rebuild

## Purpose

This is the **on-the-day operator document** for rebuilding one Raspberry Pi from CentOS to Debian using the tested RAM-rescue procedure. It is intentionally shorter and more operational than the full project runbook.

It assumes all engineering, image build, FreeSWITCH compatibility work and the non-destructive RAM-rescue round-trip test have already been completed successfully.

Do not use this document to invent or test the rescue method for the first time during the production change.

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

Active node hostname:
Active node IP:
Active node OS:

Node being rebuilt:
Node role at start: PASSIVE
Node IP:
Node MAC:
Raspberry Pi model:
SD device:
SD capacity: 32 GB

VPN router IP:
Debian image filename:
Debian image SHA512:
Git commit used:
Rollback image filename:
Rollback image SHA256:
FreeSWITCH export filename:
FreeSWITCH export SHA256:
```

Do not infer the active/passive role from hostnames. Confirm the live service state.

---

## Expected duration

For the **first passive-node migration**, book a **3-4 hour maintenance/engineering window**.

Once the first migration is proven, a subsequent Pi should normally require approximately **1.5-2.5 hours**, although a 2-3 hour working allowance remains sensible.

The 3-4 hour first-node window is intended to cover:

| Activity | Expected time |
| --- | ---: |
| Final pre-flight and role confirmation | 10-15 min |
| Final configuration/inventory export | 15-30 min |
| Full 32 GB rollback image | 20-45 min |
| Enter and validate previously proven RAM rescue | 10-20 min |
| Write/configure Debian | 15-30 min |
| Debian first boot and OS validation | 10-20 min |
| FreeSWITCH restore/reconciliation | 20-40 min |
| FreeSWITCH and functional validation | 20-40 min |
| Contingency/decision allowance | 30-60 min |

The scheduled soak period is **not** part of this hands-on migration window.

---

# RELEASE GATE 0 - Before the change window

All items below must already be true.

```text
[ ] Debian image built and checksum recorded
[ ] Exact Debian image boot-tested on representative hardware
[ ] FreeSWITCH on Debian test completed
[ ] Required FreeSWITCH modules identified
[ ] RAM-rescue build tested
[ ] CentOS -> RAM rescue -> CentOS round trip proven on passive node
[ ] VPN confirmed to terminate on router, not either Pi
[ ] SSH key access confirmed to both nodes
[ ] Laptop connected to mains power
[ ] Laptop sleep/hibernate disabled
[ ] At least 80 GB local free space when retaining both 32 GB card images
[ ] Repository working tree reviewed and exact commit recorded
[ ] Rollback procedure understood
```

**NO-GO:** if any mandatory item is unresolved, postpone the destructive change.

---

# RELEASE GATE 1 - Start-of-change validation

From the Windows administration laptop, connect the VPN and run:

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

Then confirm manually:

```text
[ ] Active node is healthy and carrying service
[ ] Passive node is healthy but not required for current production traffic
[ ] Both nodes reachable over VPN/SSH
[ ] No unrelated site/network incident is in progress
[ ] Correct node has been selected for rebuild
```

Record the start time.

```text
Actual start:
Gate 1 decision: GO / NO-GO
Notes:
```

---

# RELEASE GATE 2 - Final baseline and configuration export

Run the passive-node preflight:

```powershell
pwsh .\scripts\powershell\Invoke-PiosRemoteStage.ps1 `
  -Target <user@passive-pi-ip> `
  -RemoteScript 01-preflight.sh `
  -SiteConfig <secure-site-config-path>
```

Capture the final inventory:

```powershell
pwsh .\scripts\powershell\Invoke-PiosRemoteStage.ps1 `
  -Target <user@passive-pi-ip> `
  -RemoteScript 02-backup-inventory.sh `
  -SiteConfig <secure-site-config-path>
```

Capture FreeSWITCH configuration/runtime state:

```powershell
pwsh .\scripts\powershell\Invoke-PiosRemoteStage.ps1 `
  -Target <user@passive-pi-ip> `
  -RemoteScript 02a-export-freeswitch-config.sh `
  -SiteConfig <secure-site-config-path>
```

Copy the artifacts off the Pi:

```powershell
pwsh .\scripts\powershell\Copy-PiosArtifacts.ps1 `
  -Target <user@passive-pi-ip> `
  -OutputDirectory 'C:\pios-rebuild-artifacts\passive'
```

Verify the expected export files and checksums are present locally.

```text
[ ] Final preflight recorded
[ ] Inventory copied off-node
[ ] FreeSWITCH export copied off-node
[ ] FreeSWITCH archive checksum verified
```

**NO-GO:** do not overwrite the SD card without the FreeSWITCH export safely off-node.

---

# RELEASE GATE 3 - Full SD-card rollback image

Take the final full 32 GB rollback image using the **confirmed** whole-card device:

```powershell
pwsh .\scripts\powershell\02-full-sd-backup.ps1 `
  -Target <user@passive-pi-ip> `
  -Device /dev/mmcblk0 `
  -OutputDirectory 'C:\pios-rebuild-artifacts\passive' `
  -Label passive-centos-before-debian
```

Record:

```text
Rollback image:
Rollback image bytes:
Rollback SHA256:
Backup finish time:
```

Required:

```text
[ ] Backup command completed successfully
[ ] Raw image has expected full-card size
[ ] SHA256 sidecar created
[ ] File is on the laptop/approved off-node storage
```

**NO-GO:** if the image is incomplete, unexpectedly small or unavailable, stop.

---

# RELEASE GATE 4 - RAM-rescue readiness

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

Then load the already-tested rescue image without executing it:

```powershell
pwsh .\scripts\powershell\Invoke-PiosRemoteStage.ps1 `
  -Target <user@passive-pi-ip> `
  -RemoteScript 04-load-rescue.sh `
  -SiteConfig <secure-site-config-path>
```

Confirm the loaded rescue matches the previously tested kernel/initramfs/DTB/cmdline combination.

```text
Gate 4 decision: GO / NO-GO
Notes:
```

---

# RELEASE GATE 5 - Enter RAM rescue

Before entering rescue verify one final time:

```text
[ ] Active CentOS node still healthy
[ ] VPN stable
[ ] Full rollback image available locally
[ ] FreeSWITCH export available locally
[ ] Correct passive Pi selected
[ ] Rescue was previously round-trip tested
```

Enter rescue:

```powershell
pwsh .\scripts\powershell\Invoke-PiosRemoteStage.ps1 `
  -Target <user@passive-pi-ip> `
  -RemoteScript 05-enter-rescue.sh `
  -SiteConfig <secure-site-config-path> `
  -RemoteArgs ENTER_RESCUE
```

The normal SSH session will terminate.

Reconnect to rescue:

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
fdisk -l /dev/mmcblk0
```

Required:

```text
[ ] Rescue root is RAM/initramfs
[ ] Expected wired network interface has correct connectivity
[ ] Default route present
[ ] VPN path reaches rescue SSH
[ ] Correct 32 GB SD card is visible
[ ] Target card/child partitions are not mounted for the write
```

**STOP:** if rescue SSH cannot be reached, do not improvise a disk write.

---

# RELEASE GATE 6 - Destructive Debian write

This is the point of destructive change.

Before the command is entered, read aloud/confirm:

```text
NODE: <passive hostname/IP>
ROLE: PASSIVE
TARGET DISK: <confirmed whole SD device>
ROLLBACK IMAGE: AVAILABLE + CHECKSUMMED
DEBIAN IMAGE: APPROVED + CHECKSUM MATCHES
ACTIVE NODE: HEALTHY
```

Use the exact image-write method already proven during engineering. The Linux rescue-side writer remains the authoritative safety gate.

Example when the approved image is available to rescue:

```bash
bash /path/to/06-write-debian.sh \
  --target /dev/mmcblk0 \
  --image /path/to/approved-debian.img.xz \
  --confirm ERASE_CENTOS
```

Do **not** alter the target device or bypass the RAM-root/unmounted/checksum checks merely to make the command proceed.

Required result:

```text
DEBIAN_IMAGE_WRITE_COMPLETE=YES
```

After the write, do not reboot immediately. Complete the tested node-specific hostname/network/SSH configuration and inspect the resulting filesystems first.

Record:

```text
Write start:
Write finish:
Write result:
```

---

# RELEASE GATE 7 - First Debian boot

When the offline filesystem checks have passed:

```bash
sync
reboot
```

Wait for normal management SSH to return through the router VPN.

Run the Debian validation from PowerShell:

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

Also verify manually:

```text
[ ] Hostname correct
[ ] IP/MAC/interface correct
[ ] Default gateway correct
[ ] DNS resolution works
[ ] SSH key access works
[ ] Time/date correct
[ ] No unexpected failed systemd units
[ ] Storage layout correct
```

If Debian is reachable but validation fails, keep production on the untouched active CentOS node and troubleshoot/rebuild the passive node.

---

# RELEASE GATE 8 - FreeSWITCH restore and smoke test

Confirm all required Debian FreeSWITCH packages/modules are installed before restoring the old configuration.

Copy the verified passive-node FreeSWITCH export and its checksum sidecar to the rebuilt Pi.

Then run:

```powershell
pwsh .\scripts\powershell\Invoke-PiosRemoteStage.ps1 `
  -Target <user@passive-pi-ip> `
  -RemoteScript 07a-restore-freeswitch-config.sh `
  -SiteConfig <secure-site-config-path> `
  -RemoteArgs @('--archive','/protected/path/freeswitch-config.tgz','--confirm','APPLY_FREESWITCH_CONFIG')
```

Run the smoke test:

```powershell
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

Complete the functional test plan, including where applicable:

```text
[ ] Required modules loaded
[ ] Sofia profiles healthy
[ ] Gateways/trunks expected state
[ ] Test endpoint registration
[ ] Inbound call path
[ ] Outbound call path
[ ] Two-way RTP/audio
[ ] DTMF
[ ] Codec negotiation
[ ] Caller ID / presentation
[ ] Logging/monitoring
[ ] Reboot persistence
```

Do not fail production service over to Debian merely because the service process starts.

---

# RELEASE GATE 9 - End-of-day decision

For the first passive migration, the normal successful end state is:

```text
ACTIVE NODE: original CentOS node, still carrying production
PASSIVE NODE: Debian, rebuilt and validated
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

If the passive node passes, begin the agreed soak. **Do not rebuild the active CentOS node on the same day merely because the first rebuild finished early.**

---

# Rollback decision matrix

| Point reached | Action |
| --- | --- |
| Before entering rescue | Stop change; no OS rollback required |
| Rescue running, SD untouched | Reboot back to CentOS |
| Debian write has started/finished but rescue is alive | Restore the verified full CentOS image to the same confirmed SD device |
| Debian boots but fails validation | Keep active CentOS node serving production; repair/rebuild passive |
| FreeSWITCH restore/testing fails | Keep active CentOS node serving production; restore clean Debian config or rebuild passive |
| Later production failover fails | Fail service back to the untouched CentOS node |

A rollback is a successful controlled outcome when a release gate fails; do not continue solely to avoid recording a failed change.

---

# Absolute stop conditions

Stop rather than improvise if any of the following occurs:

```text
- VPN/router connectivity becomes unreliable
- active/passive role cannot be proved
- active production node becomes unhealthy
- target disk identity is uncertain
- rollback image is missing or suspect
- FreeSWITCH export is missing or suspect
- rescue readiness does not pass
- rescue cannot be reached over the VPN
- rescue root is not demonstrably RAM-resident
- target card or a child partition remains mounted
- Debian image checksum does not match the approved artifact
- unexpected hardware/boot layout is observed
- unresolved Severity 1 or Severity 2 FreeSWITCH defect exists
```

---

# Separate production failover release

After the rebuilt Debian passive node has completed its **24-48 hour passive soak**, schedule a separate controlled production failover window of approximately **1-2 hours**.

At that later release:

1. confirm both nodes healthy;
2. take/refesh any configuration export that may have changed;
3. move service from CentOS active to Debian;
4. test inbound/outbound calls, RTP, DTMF, caller ID and gateways immediately;
5. if acceptance fails, return service to CentOS;
6. if acceptance passes, keep the former CentOS active node unchanged during the agreed production soak;
7. only after production soak approval schedule the second-node rebuild.

This deliberately separates **OS migration risk** from **production failover risk**.
