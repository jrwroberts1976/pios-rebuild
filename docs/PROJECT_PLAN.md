# Project Plan

## Objective

Replace the current CentOS installations on remote two-node Raspberry Pi FreeSWITCH sites with Debian 13 while maintaining service continuity and preserving a practical rollback path.

## Supported source profiles

| Profile | Current hardware / OS | Target |
| --- | --- | --- |
| `PI3-CENTOS7` | Raspberry Pi 3 / CentOS 7 | Debian 13 arm64 |
| `PI4-CENTOS9` | Raspberry Pi 4 / CentOS 9 | Debian 13 arm64 |

The workflow is shared, but the rescue environment and hardware validation are profile-specific. A Pi 3 / CentOS 7 rescue test does not approve a Pi 4 / CentOS 9 migration. See `PI4_CENTOS9.md` for the Pi 4 profile.

## Key design

Each site has two Pi nodes. The passive node is the proving node. The active CentOS node remains untouched and continues to provide service while the passive node is rebuilt, tested and soaked. Only after the Debian passive node is proven do we perform service failover. The former active node is rebuilt last.

## Prerequisites

### Administration laptop/workstation

The laptop used to connect through the site router-hosted VPN is part of the recovery design and must pass `ADMIN_LAPTOP_PREREQUISITES.md` before either Pi is touched.

At minimum it must have stable VPN access, key-based SSH to both nodes, the required PowerShell/OpenSSH/Git or Linux/WSL tools, protected local storage for rollback images and migration artifacts, mains power, sleep/hibernate disabled and the repository checked out at an exact recorded commit.

Both Pi estates use 32 GB SD cards. When retaining both full raw card images on the workstation, **80 GB free space is the recommended release-day minimum**.

### Site and platform prerequisites

1. Select the correct migration profile and verify the expected Pi model and source CentOS version.
2. Confirm router-hosted VPN remains available independently of either Pi.
3. Confirm both Pi roles, IPs, MAC addresses, hostnames and current FreeSWITCH responsibilities.
4. Export and securely copy off-node the complete FreeSWITCH configuration/runtime manifest from **each** node.
5. Capture SIP trunk, extension, gateway, codec, dialplan, ACL, NAT, RTP, certificate, script and firewall requirements.
6. Build a reproducible Debian 13 arm64 image containing the required operating-system/migration tooling and chosen FreeSWITCH packages where practical.
7. Test the exact image and FreeSWITCH on representative hardware for the selected profile.
8. Verify `kexec` support and build/test a RAM-rescue environment on the passive node for that profile.
9. Take an off-node full 32 GB SD-card image before destructive work.
10. Keep the active CentOS node untouched until the passive Debian node has passed production soak.

## Workstreams

### WS0 - Administration workstation readiness

- establish and test the router VPN;
- verify SSH keys against both nodes;
- install required local CLI tools;
- verify at least 80 GB free when using the two-card rollback workflow;
- create protected artifact directories;
- update the repository using `git pull --ff-only` before the change;
- record the exact repository commit used;
- make no further Git updates during the release;
- prove the VPN is stable enough for sustained backup/image transfer.

**Exit gate:** workstation preflight passes and rollback artifacts can be retained locally throughout the change.

### WS1 - Discovery and baseline

- Select `PI3-CENTOS7` or `PI4-CENTOS9`.
- Run preflight on both nodes.
- Prove model, architecture and source OS version match the selected profile.
- Record active/passive state and network configuration.
- Export FreeSWITCH configuration/runtime status from both nodes.
- Record package/service inventory and call-flow dependencies.
- Establish acceptance criteria and rollback triggers.

**Exit gate:** both nodes fully identified, profile matches, current service behaviour documented and FreeSWITCH exports copied to secure off-node storage with verified checksums.

### WS2 - FreeSWITCH configuration migration package

For each CentOS node:

- identify the actual FreeSWITCH configuration root;
- archive the complete configuration tree preserving metadata;
- capture FreeSWITCH version, loaded modules, Sofia profile/gateway state and installed package list;
- capture supplementary scripts/data paths where present;
- create and verify archive checksums;
- copy the export away from the node before rebuild.

The export is a **sensitive artifact** because it may contain SIP credentials, event-socket passwords, certificates/provider information and other secrets. It must never be committed to GitHub.

On Debian, install/reconcile the required FreeSWITCH modules first, then use `07a-restore-freeswitch-config.sh` to back up the fresh Debian config and overlay the exported site config. CentOS 7 and CentOS 9 may differ in package/service/network/firewall details; do not assume an OS-level one-for-one copy.

**Exit gate:** export/restore procedure demonstrated on a non-production or passive Debian test instance and all required site modules identified.

### WS3 - Debian image engineering

- Start from the official Debian 13 Raspberry Pi arm64 image.
- Pin the source image filename and SHA512 checksum.
- Add required administration, troubleshooting and migration tooling.
- Configure first-boot behaviour without embedding production secrets.
- Prepare SSH key injection and network configuration process.
- Add the selected FreeSWITCH installation/bootstrap mechanism.
- Produce an image manifest and checksum.
- Ensure any temporary repository credential used during image construction is removed before finalisation.
- Boot-test the exact resulting image on each Raspberry Pi hardware family on which it will be deployed.

**Exit gate:** reproducible image passes validation on the target profile hardware: Pi 3 for `PI3-CENTOS7`, Pi 4 for `PI4-CENTOS9`.

### WS4 - FreeSWITCH Debian validation

Validate service start, `fs_cli`, required modules, migrated configuration, SIP profiles, endpoint registration, gateways/trunks, inbound/outbound calls, two-way RTP/audio, DTMF, codec negotiation, caller ID, failover behaviour, logs/monitoring and reboot persistence.

**Exit gate:** test plan passes with no unresolved Severity 1 or Severity 2 defects.

### WS5 - RAM-rescue proof on passive node

- Build rescue initramfs using a kernel/modules combination suitable for the selected hardware/source-OS profile.
- Configure rescue SSH on a separate port.
- Load with `kexec` without executing first.
- Validate loaded rescue metadata.
- Enter rescue and reconnect over router VPN.
- Prove networking, SSH, RAM-root and SD-card visibility.
- Reboot without changing the SD card.
- Prove the original CentOS version returns.

**Exit gate:** `CentOS -> RAM rescue -> same CentOS` round trip passes on the exact target profile.

### WS6 - Passive-node rebuild

- Take/verify final off-node backup and FreeSWITCH export.
- Enter already-proven profile-specific RAM rescue.
- Verify the whole target device and that it/its children are unmounted.
- Stream/write the verified Debian image to the whole SD-card device.
- Mount and inspect the new Debian filesystems while rescue remains alive.
- Apply node-specific network/SSH/hostname configuration.
- Reboot into Debian and validate Debian.
- Ensure required FreeSWITCH packages/modules are installed.
- Restore the passive node's saved FreeSWITCH configuration.
- Run FreeSWITCH smoke/functional tests.

**Exit gate:** passive node is reachable, Debian validation passes, FreeSWITCH configuration is restored/validated and the node is ready for controlled service testing.

### WS7 - Passive-node soak and controlled failover

- Keep original active CentOS node carrying production service.
- Exercise Debian node using test endpoints/routes where possible.
- Observe CPU, memory, storage, temperature, SIP registrations, RTP and logs.
- Run repeated reboot tests.
- Perform a controlled production failover only after soak approval.
- Confirm all critical call paths.

**Exit gate:** Debian node carries production service successfully for the agreed soak period.

### WS8 - Former-active rebuild

- Keep the now-active Debian node in service.
- Re-export the former active node's FreeSWITCH configuration immediately before migration if configuration may have changed.
- Repeat the proven backup/rescue/rebuild process using the same profile.
- Restore that node's own FreeSWITCH configuration and passive role.
- Re-establish resilience and test failback/failover.

**Exit gate:** both nodes are Debian 13 and active/passive resilience is restored.

## Indicative timeline

| Stage | Indicative window | Purpose |
| --- | ---: | --- |
| Admin laptop/VPN readiness | 1-2 hours | Tooling, storage, keys and sustained connectivity |
| Discovery + FreeSWITCH export | 0.5 day | Capture current state and hard prerequisites |
| Golden image build + static validation | 0.5-1 day | Produce repeatable Debian image |
| Hardware-specific image + FreeSWITCH tests | 1 day | Prove target Pi family and telephony behaviour |
| Passive rescue round-trip test | 0.5 day | Prove profile-specific remote recovery mechanism |
| First passive rebuild | 3-4 hours | First production-site migration for that profile |
| Passive soak/test traffic | 24-48 hours | Catch stability, registration, RTP and resource issues |
| Controlled failover + acceptance | 1-2 hours | Move live service to Debian and validate |
| Production soak | 48 hours | Confirm sustained stability under real traffic |
| Second-node rebuild | 1.5-2.5 hours typical | Repeat proven process on former active node |
| Dual-node/failover acceptance | 0.5 day | Restore and prove resilience |

A cautious end-to-end programme remains approximately **5-7 elapsed days**, largely because of the passive and production soak periods. Hands-on engineering time is materially lower.

## Rollback strategy

Before SD overwrite, normal reboot returns to the existing CentOS installation. During RAM-rescue write/configuration, if rescue remains alive and Debian is not satisfactory, restore the verified full-card image for that node and reboot. After Debian boots but before failover, the active CentOS peer remains in service. After failover, restore service to the untouched CentOS peer if production acceptance fails. Do not rebuild the original active node until the Debian node has completed production soak.

## Definition of done

- Administration laptop prerequisite gate passed and evidence recorded.
- Selected profile matches the actual Pi model and source CentOS version.
- Both Raspberry Pi nodes run Debian 13.
- Required FreeSWITCH version/modules are installed and documented.
- Each node's intended FreeSWITCH configuration has been exported, restored and validated.
- All critical inbound/outbound call paths, RTP/DTMF/codec behaviour pass.
- Monitoring/logging/backup requirements pass.
- Active/passive failover and failback are demonstrated.
- Reboot tests pass on both nodes.
- No CentOS production dependency remains.
- Runbook and test evidence are updated with actual site values.
