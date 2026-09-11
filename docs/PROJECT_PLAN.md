# Project Plan

## Objective

Replace CentOS 7 on both remote Raspberry Pi 3 FreeSWITCH nodes with Debian 13 while maintaining service continuity and preserving a practical rollback path.

## Key design

The site has two Pi nodes. The passive node is the proving node. The active CentOS node remains untouched and continues to provide service while the passive node is rebuilt, tested and soaked. Only after the Debian passive node is proven do we perform service failover. The former active node is rebuilt last.

## Prerequisites

### Administration laptop/workstation

The laptop used to connect through the site VPN is part of the recovery design and must pass `docs/ADMIN_LAPTOP_PREREQUISITES.md` before either Pi is touched.

At minimum it must have:

- stable router-hosted VPN access to the remote site;
- key-based SSH access to both Pi nodes;
- SSH/SCP or SFTP, rsync, Git, curl/wget, tar, gzip, xz, zstd, checksum tools, `dd` and `pv`;
- enough protected local disk space for both full SD-card images, the Debian image, FreeSWITCH exports and test evidence;
- mains power and sleep/hibernate disabled during migration;
- the migration repository checked out at a known commit;
- the verified CentOS rollback images immediately accessible throughout the migration.

Run:

```bash
./scripts/00-admin-laptop-preflight.sh \
  --router <router-ip> \
  --active <user@active-pi-ip> \
  --passive <user@passive-pi-ip> \
  --min-free-gb <calculated-minimum>
```

**Exit gate:** `ADMIN_LAPTOP_PREFLIGHT=PASS` and the manual power/sleep/VPN gates are confirmed.

### Site and platform prerequisites

1. Confirm router-hosted VPN remains available independently of either Pi.
2. Confirm both Pi roles, IPs, MAC addresses, hostnames and current FreeSWITCH responsibilities.
3. Export and securely copy off-node the complete FreeSWITCH configuration/runtime manifest from **each** node using `scripts/02a-export-freeswitch-config.sh`.
4. Capture SIP trunk, extension, gateway, codec, dialplan, ACL, NAT, RTP, certificate, script and firewall requirements.
5. Build a reproducible Debian 13 arm64 image containing the required operating-system/migration tooling and chosen FreeSWITCH 1.11.x packages where practical.
6. Test the exact image and FreeSWITCH on Debian 13 before any production failover.
7. Verify `kexec` support and build/test a RAM-rescue environment on the passive node.
8. Take an off-node full SD-card image before destructive work.
9. Keep the active CentOS node untouched until the passive Debian node has passed production soak.

## Workstreams

### WS0 - Administration workstation readiness

- establish and test the router VPN;
- verify SSH keys against both nodes;
- install required local CLI tools;
- calculate storage required from the actual SD-card capacities;
- create protected artifact directories;
- record the exact repository commit used;
- verify the laptop will remain powered and awake;
- prove the VPN is stable enough for sustained backup/image transfer.

**Exit gate:** workstation preflight passes and rollback artifacts can be retained locally throughout the change.

### WS1 - Discovery and baseline

- Run preflight on both nodes.
- Record active/passive state.
- Record current network configuration.
- Export FreeSWITCH configuration and runtime status from both nodes.
- Record package/service inventory.
- Record call-flow and trunk dependencies.
- Establish acceptance criteria and rollback triggers.

**Exit gate:** Both nodes fully identified; current service behaviour documented; both FreeSWITCH exports copied to secure off-node storage and checksums verified.

### WS2 - FreeSWITCH configuration migration package

For each CentOS node:

- identify the actual FreeSWITCH configuration root (`/etc/freeswitch` or `/usr/local/freeswitch/conf`);
- archive the complete configuration tree preserving permissions/metadata;
- capture FreeSWITCH version;
- capture loaded modules;
- capture Sofia profile/gateway state;
- capture installed FreeSWITCH package list;
- capture supplementary scripts/data paths where present;
- create and verify archive checksums;
- copy the export away from the node before rebuild.

The export is a **sensitive artifact** because it may contain SIP credentials, event-socket passwords, certificates/provider information and other secrets. It must never be committed to GitHub.

On Debian, install/reconcile the required FreeSWITCH modules first, then use `scripts/07a-restore-freeswitch-config.sh` to back up the fresh Debian config and overlay the exported site config. Any CentOS-to-Debian module/package difference must be resolved before production testing.

**Exit gate:** Export/restore procedure demonstrated on a non-production or passive Debian test instance and all required site modules identified.

### WS3 - Debian image engineering

- Start from the official Debian 13 Raspberry Pi arm64 image.
- Pin the source image filename and SHA512 checksum.
- Add required administration, troubleshooting and migration tooling.
- Configure first-boot behaviour without embedding production secrets.
- Prepare SSH key injection and network configuration process.
- Add the selected FreeSWITCH installation/bootstrap mechanism.
- Produce an image manifest and checksum.
- Ensure any temporary package-repository credential used during image construction is removed before the artifact is finalised.

**Exit gate:** Reproducible image passes image validation and boots successfully on representative Raspberry Pi 3 hardware where available.

### WS4 - FreeSWITCH Debian validation

The project must prove the exact selected FreeSWITCH version, modules, migrated configuration and telephony behaviour required by this site on Debian 13.

Validate:

- service starts cleanly;
- `fs_cli` works;
- required modules load;
- migrated configuration loads without unresolved errors;
- SIP profiles start;
- internal endpoints can register;
- gateways/trunks register or reach the expected state;
- inbound calls route correctly;
- outbound calls route correctly;
- two-way RTP/audio works;
- DTMF works;
- codec negotiation matches production requirements;
- caller ID and number presentation are correct;
- failover behaviour is understood;
- logs and monitoring are available;
- reboot preserves service.

**Exit gate:** Test plan passes with no unresolved Severity 1 or Severity 2 defects.

### WS5 - RAM-rescue proof on passive node

- Build rescue initramfs using the currently working CentOS kernel/modules where practical.
- Configure rescue SSH on a separate port.
- Load with `kexec` without executing first.
- Validate loaded rescue metadata.
- Enter rescue.
- Reconnect over router VPN.
- Prove networking, SSH and SD-card visibility.
- Reboot without changing the SD card.
- Prove CentOS returns.

**Exit gate:** CentOS -> RAM rescue -> CentOS round trip passes.

### WS6 - Passive-node rebuild

- Take/verify final off-node backup and FreeSWITCH export.
- Enter already-proven RAM rescue.
- Verify target device and that it is unmounted.
- Stream the verified Debian image to the whole SD-card device.
- Mount and inspect the new Debian filesystems while rescue remains alive.
- Apply node-specific network/SSH/hostname configuration.
- Reboot into Debian.
- Validate Debian.
- Ensure the required FreeSWITCH package/module set is installed.
- Restore the passive node's saved FreeSWITCH configuration.
- Run FreeSWITCH smoke/functional tests.

**Exit gate:** Passive node is reachable, FreeSWITCH configuration is restored and validated, and the node is ready for controlled service testing.

### WS7 - Passive-node soak and controlled failover

- Keep original active CentOS node carrying production service.
- Exercise Debian node using test endpoints/routes where possible.
- Observe CPU, memory, storage, temperature, SIP registrations, RTP and logs.
- Run repeated reboot tests.
- Perform a controlled production failover to the Debian node.
- Confirm all critical call paths.

**Exit gate:** Debian node carries production service successfully for the agreed soak period.

### WS8 - Former-active rebuild

- Keep the now-active Debian node in service.
- Re-export the former active node's FreeSWITCH configuration immediately before migration if configuration may have changed since baseline.
- Repeat the proven backup/rescue/rebuild process on the former active node.
- Restore that node's own FreeSWITCH configuration and passive role.
- Re-establish resilience and test failback/failover.

**Exit gate:** Both nodes are Debian 13 and active/passive resilience is restored.

## Indicative test timeline

This is an elapsed testing plan, not a promise of implementation duration.

| Stage | Indicative window | Purpose |
| --- | ---: | --- |
| Admin laptop/VPN readiness | 1-2 hours | Tooling, storage, keys and sustained connectivity |
| Discovery + FreeSWITCH config export | 0.5 day | Capture current state, config and hard prerequisites |
| Golden image build + static validation | 0.5-1 day | Produce repeatable Debian image |
| FreeSWITCH Debian/config-restore tests | 1 day | Prove packages/modules, restored config and basic calling |
| Passive rescue round-trip test | 0.5 day | Prove remote recovery mechanism |
| Passive Debian rebuild + config restore + smoke tests | 0.5 day | Perform first production-site rebuild |
| Passive soak/test traffic | 24-48 hours | Catch stability, registration, RTP and resource issues |
| Controlled failover + production acceptance | 1-2 hours | Move live service to Debian node and validate |
| Production soak | 48 hours | Confirm sustained stability under real traffic |
| Former-active rebuild | 0.5 day | Rebuild second node using proven process |
| Dual-node/failover acceptance | 0.5 day | Restore and prove resilience |

A cautious end-to-end programme is approximately **5-7 elapsed days**, largely because of the 24-48 hour passive observation period and 48 hour production soak. Hands-on engineering time is materially lower than the elapsed time.

## Rollback strategy

### Before SD overwrite

Normal reboot returns to CentOS.

### During RAM-rescue write/configuration

If rescue remains alive and Debian is not satisfactory, restore the previously captured full CentOS SD image over the VPN, sync, then reboot.

### After Debian successfully boots but before failover

The active CentOS node remains in service. Rebuild or restore the passive node without production service impact.

### FreeSWITCH configuration restore

`07a-restore-freeswitch-config.sh` first backs up the fresh Debian FreeSWITCH configuration. If the migrated configuration is incompatible, restore that fresh config, correct package/module differences, or rebuild the passive node while production remains on CentOS.

### After failover

If Debian production acceptance fails, restore service to the untouched CentOS active node, provided it has not yet been rebuilt.

### Second-node migration

Do not rebuild the original active CentOS node until the Debian node has completed production soak and rollback confidence is acceptable.

## Definition of done

- Administration laptop prerequisite gate passed and evidence recorded.
- Both Raspberry Pi nodes run Debian 13.
- Required FreeSWITCH version/modules are installed and documented.
- Each node's intended FreeSWITCH configuration has been exported, restored and validated.
- All critical inbound/outbound call paths pass.
- RTP/DTMF/codec behaviour passes.
- Monitoring/logging/backup requirements pass.
- Active/passive failover and failback are demonstrated.
- Reboot tests pass on both nodes.
- No CentOS 7 production dependency remains.
- Runbook and test evidence are updated with actual site values.