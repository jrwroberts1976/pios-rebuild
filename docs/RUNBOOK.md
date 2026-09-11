# Remote Rebuild Runbook

## Scope

This runbook covers the staged rebuild of a two-node Raspberry Pi FreeSWITCH site from CentOS to Debian 13 over a router-hosted VPN with no onsite engineer.

Supported source profiles:

| Profile | Source | Target |
| --- | --- | --- |
| `PI3-CENTOS7` | Raspberry Pi 3 / CentOS 7 | Debian 13 arm64 |
| `PI4-CENTOS9` | Raspberry Pi 4 / CentOS 9 | Debian 13 arm64 |

The overall process is shared, but the rescue environment is profile-specific. A Pi 3 / CentOS 7 rescue build is not approved for Pi 4 / CentOS 9 unless separately tested and evidenced. See `PI4_CENTOS9.md`.

## Safety model

- The VPN terminates on the router and is independent of both Pi nodes.
- The passive node is rebuilt first while the active CentOS node continues service.
- The administration laptop remains available throughout backup, rescue, image streaming and rollback.
- The existing CentOS SD card is not overwritten until the RAM-rescue path has been proven non-destructively on the selected profile.
- A full block-level CentOS image and separate FreeSWITCH configuration export are retained off-node.
- The original active CentOS node is not rebuilt until the Debian node has passed production soak.
- All profile, device and checksum gates fail closed.

## Record site values

```text
MIGRATION_PROFILE=PI3-CENTOS7 / PI4-CENTOS9
ACTIVE_NODE_HOSTNAME=
ACTIVE_NODE_IP=
ACTIVE_NODE_MAC=
ACTIVE_NODE_OS=
PASSIVE_NODE_HOSTNAME=
PASSIVE_NODE_IP=
PASSIVE_NODE_MAC=
PASSIVE_NODE_OS=
PASSIVE_PI_MODEL=
VPN_ROUTER_IP=
TARGET_SD_DEVICE=
TARGET_SD_CAPACITY=32 GB
```

Do not infer active/passive state from hostname alone. Confirm actual service state.

---

# Phase -1 - Administration laptop prerequisite

Read `ADMIN_LAPTOP_PREREQUISITES.md` and, for Windows, `POWERSHELL.md`.

The laptop/workstation must have stable VPN access, key-based SSH to both Pi nodes, sufficient protected local storage, required tools, mains power, sleep/hibernate disabled, the repository checked out at a known commit and verified rollback artifacts immediately accessible.

For two 32 GB card images, use **80 GB free** as the recommended release-day workstation minimum.

**GO gate:** workstation preflight passes and manual power/sleep/VPN-reconnect gates are confirmed.

---

# Phase 0 - Select profile, build and test Debian image

Before changing either production Pi:

1. select `PI3-CENTOS7` or `PI4-CENTOS9`;
2. copy the matching site configuration example to protected storage;
3. obtain the official Debian 13 Raspberry Pi arm64 image and verify its official checksum;
4. use `00-build-debian-image.sh` and `IMAGE_BUILD.md` to produce the project golden image;
5. record the output SHA512 and repository commit;
6. boot the exact output image on representative hardware for the selected profile;
7. install/test the selected FreeSWITCH version and required modules;
8. complete the relevant tests in `FREESWITCH_TEST_PLAN.md`;
9. retain the exact approved image artifact used in testing.

**GO gate:** approved Debian image checksum and hardware-specific FreeSWITCH test evidence exist.

---

# Phase 1 - Baseline both production nodes

Create a protected site configuration from the matching profile example. Do not commit production secrets.

For Pi 4 / CentOS 9 use:

```text
config/site-pi4-centos9.env.example
```

Before the normal node preflight, run the dedicated **source kexec OS readiness audit on both CentOS nodes**:

```bash
sudo bash scripts/00-source-kexec-preflight.sh
```

This stage is read-only. It does not load a kernel, execute kexec, reboot, change boot files or write the SD card.

Record the final result:

```text
KEXEC_OS_READY=YES
```

or:

```text
KEXEC_OS_READY=PROVISIONAL
```

or:

```text
KEXEC_OS_READY=NO
```

Rules:

- `YES` means the static source-OS prerequisites pass, but a same-kernel load/unload proof is still required before rescue execution.
- `PROVISIONAL` means no hard failure was detected but one or more items need review; perform and record the controlled same-kernel load/unload proof documented in `SOURCE_PI_PREREQUISITES.md` before proceeding to rescue.
- `NO` is a hard stop. Do not attempt `kexec -e` or build a production migration around that kernel until the failed prerequisite is resolved.

Then run the normal preflight, generic inventory and FreeSWITCH export stages. From PowerShell, use `Invoke-PiosRemoteStage.ps1`; from Linux/WSL the scripts can be invoked directly.

The preflight must prove:

- Pi model matches the profile;
- architecture matches;
- source OS ID/version matches;
- root and target devices are understood;
- wired network/default route are present;
- FreeSWITCH state is captured;
- kexec/boot information is recorded.

Copy all inventory and FreeSWITCH export artifacts to the administration laptop/approved secure storage and verify checksums.

**GO gate:** both node inventories and both verified FreeSWITCH exports are safely off-node, and neither source node has `KEXEC_OS_READY=NO`.

---

# Phase 2 - Passive-node full disk backup

Take a full block image of the passive Pi SD card and save it off-node. Use the actual whole-card device confirmed by preflight; do not assume `/dev/mmcblk0` without checking.

For Windows/PowerShell use:

```powershell
pwsh .\scripts\powershell\02-full-sd-backup.ps1 `
  -Target <user@passive-pi-ip> `
  -Device <confirmed-whole-card-device> `
  -OutputDirectory 'C:\pios-rebuild-artifacts\passive' `
  -Label passive-centos-before-debian
```

The backup must be the expected full-card size and have a SHA-256 sidecar.

**GO gate:** full off-node image exists and verification passes.

---

# Phase 3 - Passive rescue readiness

Run `03-rescue-readiness.sh` using the selected profile configuration.

The gate checks Raspberry Pi identity, architecture/kernel, target SD device, wired network/default route, kexec userspace/kernel capability, memory and candidate kernel/initramfs/DTB files.

If it reports `RESCUE_READY=NO`, stop.

If the earlier source kexec audit returned `PROVISIONAL`, the controlled same-kernel `kexec -l` / `kexec -u` proof must already have passed and been recorded before this phase is approved.

---

# Phase 4 - Build the profile-specific RAM rescue environment

The rescue environment must contain enough to operate independently of the SD card:

- known-compatible kernel/modules for the selected Pi model and CentOS version;
- RAM-root initramfs;
- required Pi Ethernet and SD/MMC support;
- network tools and known addressing behaviour;
- Dropbear or equivalent SSH server;
- approved SSH public key;
- block/filesystem tools;
- checksum/decompression tools;
- watchdog support where proven.

For Pi 4 / CentOS 9, build and test the rescue specifically against that platform. Do not reuse the Pi 3 rescue merely because the commands look similar.

---

# Phase 5 - Load rescue without executing it

After the exact kernel/initramfs/DTB arguments are reviewed, run `04-load-rescue.sh`.

This loads rescue into the kexec slot only. Verify the loaded state where supported. If anything is unexpected, stop before entering rescue.

---

# Phase 6 - Non-destructive rescue proof

Enter rescue with the explicit `ENTER_RESCUE` confirmation. The normal CentOS SSH session will end.

Reconnect over the router VPN to the rescue SSH port, normally TCP/2222, and verify:

```bash
findmnt /
mount
ip -br addr
ip route
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL
fdisk -l <confirmed-whole-card-device>
```

Required result:

- rescue root is RAM/initramfs;
- expected Ethernet works;
- VPN path reaches rescue SSH;
- correct SD card is visible;
- SD card is not the rescue root;
- no target/child partition will be mounted during the write.

**Do not write Debian during this first rescue test.** Reboot normally and prove the original CentOS version and FreeSWITCH return.

For Pi 4 / CentOS 9, the required evidence is specifically:

```text
CentOS 9 -> Pi 4 RAM rescue -> CentOS 9
```

**GO gate:** profile-specific rescue round trip succeeds over the VPN.

---

# Phase 7 - Real passive-node migration

Repeat the now-proven rescue process and reconnect to RAM rescue.

Before destructive work, re-confirm VPN stability, node identity/role, target device, unmounted state, approved Debian checksum, verified full CentOS disk backup and FreeSWITCH export.

Run the Linux rescue-side writer using the confirmed whole-card target and explicit `ERASE_CENTOS` confirmation. The write script must remain the authoritative RAM-root, device, mount and checksum gate.

After the write completes, **do not reboot yet**. Reread the partition table, mount the new Debian filesystems and apply only the tested node-specific hostname/network/SSH configuration. Inspect `/etc/os-release`, boot files and filesystem configuration before rebooting.

---

# Phase 8 - First Debian boot and OS validation

Reboot into Debian and reconnect through the router VPN. Run `07-validate-debian.sh`.

Required result:

```text
DEBIAN_VALIDATION=PASS
```

If Debian is unhealthy but reachable, troubleshoot/rebuild the passive node while the untouched CentOS active node continues production service.

---

# Phase 9 - Restore FreeSWITCH configuration

Before applying the old configuration, ensure Debian has the required FreeSWITCH packages/modules identified during baseline and image tests.

Copy the passive node's verified FreeSWITCH export and checksum sidecar to Debian, then run `07a-restore-freeswitch-config.sh` with the explicit `APPLY_FREESWITCH_CONFIG` confirmation.

Do not assume CentOS 7 or CentOS 9 package/module names map one-for-one to Debian. Reconcile missing/deprecated modules before failover.

Run `08-freeswitch-smoke-test.sh --start` and complete `FREESWITCH_TEST_PLAN.md`.

---

# Phase 10 - Passive-node soak

Keep the Debian node passive for **24-48 hours** while the original CentOS node remains active. Review FreeSWITCH uptime, profiles/gateways/registrations, CPU/RAM/swap, storage, temperature, logs, time synchronisation, monitoring and test SIP/RTP paths.

Do not rebuild the active CentOS node yet.

---

# Phase 11 - Controlled production failover

Preconditions: passive Debian node passed OS and FreeSWITCH tests, passive soak completed, active CentOS node healthy, current config/export backups exist and rollback is ready.

Use the site's existing active/passive mechanism to move production service to Debian. Immediately test inbound/outbound calls, two-way audio, DTMF, caller ID, SIP registration/gateway state and site-specific call flows.

If a Severity 1 or Severity 2 issue appears, fail service back to the untouched CentOS node.

---

# Phase 12 - Production soak

Operate the Debian node as active for approximately **48 hours**. Keep the original CentOS node unchanged and available for rollback throughout this period.

Only after production soak passes is the second rebuild approved.

---

# Phase 13 - Rebuild the former active node

Re-export its FreeSWITCH configuration if it may have changed since baseline, copy/verify it off-node, then repeat the proven profile-specific preflight, backup, rescue, Debian write, validation, FreeSWITCH restore and test process.

---

# Phase 14 - Dual-node resilience acceptance

With both nodes on Debian 13, validate unique node identity/IPs, normal active/passive roles, deliberate failover/failback, critical call paths, individual node reboots and monitoring/logging identity.

---

# Emergency rollback matrix

| State | Rollback |
| --- | --- |
| Before rescue | No OS change required |
| Rescue loaded but not executed | Unload kexec or reboot normally |
| Rescue running, SD untouched | Reboot to original CentOS |
| Debian write complete, rescue still alive | Restore verified full-card CentOS image to the same confirmed SD device |
| Debian booted, before failover | Active CentOS peer continues service; repair/rebuild passive |
| FreeSWITCH config restore fails | Restore fresh Debian FreeSWITCH config and reconcile modules/config |
| Debian active after failover | Fail service back to untouched CentOS peer |
| Both nodes already Debian | Use retained system/config backups and documented recovery procedure |

# Absolute stop conditions

Stop rather than improvise if the admin-laptop prerequisite gate fails; VPN/router connectivity is unstable; profile/model/source OS does not match; active/passive role is uncertain; target disk identity is uncertain; rollback image or FreeSWITCH export is unavailable/suspect; source kexec readiness is `NO`; required same-kernel load/unload proof has not passed where needed; rescue proof has not passed for the exact profile; rescue cannot be reached; Debian image checksum differs; or FreeSWITCH Debian testing has an unresolved Severity 1/2 defect.
