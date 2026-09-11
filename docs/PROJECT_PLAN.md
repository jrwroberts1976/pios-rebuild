# Project Plan

## Objective

Replace CentOS 7 on both remote Raspberry Pi 3 FreeSWITCH nodes with Debian 13 while maintaining service continuity and preserving a practical rollback path.

## Key change to the original approach

The site has two Pi nodes. This allows the passive node to be used as the proving node. The active CentOS node remains untouched and continues to provide service while the passive node is rebuilt, tested and soaked. Only after the Debian passive node is proven do we perform service failover. The former active node is rebuilt last.

## Prerequisites

1. Confirm router-hosted VPN remains available independently of either Pi.
2. Confirm both Pi roles, IPs, MAC addresses, hostnames and current FreeSWITCH responsibilities.
3. Export and back up the complete FreeSWITCH configuration from both nodes.
4. Capture SIP trunk, extension, gateway, codec, dialplan, ACL, NAT, RTP and firewall requirements.
5. Build a reproducible Debian 13 arm64 image containing the required operating-system and migration tooling.
6. Test FreeSWITCH on Debian 13 before any production failover.
7. Verify `kexec` support and build a RAM-rescue environment on the passive node.
8. Take an off-node full SD-card image before destructive work.

## Workstreams

### WS1 - Discovery and baseline

- Run preflight on both nodes.
- Record active/passive state.
- Record current network configuration.
- Export FreeSWITCH configuration and runtime status.
- Record package/service inventory.
- Record call-flow and trunk dependencies.
- Establish acceptance criteria and rollback triggers.

**Exit gate:** Both nodes fully identified and current service behaviour documented.

### WS2 - Debian image engineering

- Start from the official Debian 13 Raspberry Pi arm64 image.
- Pin the source image filename and SHA512 checksum.
- Add required administration, troubleshooting and migration tooling.
- Configure first-boot behaviour without embedding secrets.
- Prepare SSH key injection and network configuration process.
- Add FreeSWITCH installation/bootstrap mechanism.
- Produce an image manifest and checksum.

**Exit gate:** Reproducible image passes image validation and boots successfully on representative Raspberry Pi 3 hardware where available.

### WS3 - FreeSWITCH Debian validation

FreeSWITCH 1.11.0 added Debian 13 Trixie support. The project must still prove the exact modules, configuration and telephony behaviour required by this site.

Validate:

- service starts cleanly;
- `fs_cli` works;
- required modules load;
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

### WS4 - RAM-rescue proof on passive node

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

### WS5 - Passive-node rebuild

- Take/verify final off-node backup.
- Enter already-proven RAM rescue.
- Verify target device and that it is unmounted.
- Stream verified Debian image to the whole SD-card device.
- Mount and inspect the new Debian filesystems while rescue remains alive.
- Apply node-specific network/SSH/hostname configuration.
- Reboot into Debian.
- Run OS and FreeSWITCH smoke tests.

**Exit gate:** Passive node is reachable, stable and ready for controlled service testing.

### WS6 - Passive-node soak and controlled failover

- Keep original active CentOS node carrying production service.
- Exercise Debian node using test endpoints/routes where possible.
- Observe CPU, memory, storage, temperature, SIP registrations, RTP and logs.
- Run repeated reboot tests.
- Perform a controlled production failover to the Debian node.
- Confirm all critical call paths.

**Exit gate:** Debian node carries production service successfully for the agreed soak period.

### WS7 - Former-active rebuild

- Keep the now-active Debian node in service.
- Repeat the proven backup/rescue/rebuild process on the former active node.
- Restore FreeSWITCH configuration and passive role.
- Re-establish resilience and test failback/failover.

**Exit gate:** Both nodes are Debian 13 and active/passive resilience is restored.

## Indicative test timeline

This is an elapsed testing plan rather than a promise of implementation duration.

| Stage | Indicative window | Purpose |
| --- | ---: | --- |
| Discovery/baseline | 0.5 day | Capture current state and hard prerequisites |
| Golden image build + static validation | 0.5-1 day | Produce repeatable Debian image |
| FreeSWITCH Debian lab/sandbox tests | 1 day | Prove install, modules and basic calling |
| Passive rescue round-trip test | 0.5 day | Prove remote recovery mechanism |
| Passive Debian rebuild + smoke tests | 0.5 day | Perform first production-site rebuild |
| Passive soak/test traffic | 24-48 hours | Catch stability, registration, RTP and resource issues |
| Controlled failover + production acceptance | 1-2 hours | Move live service to Debian node and validate |
| Production soak | 48 hours | Confirm sustained stability under real traffic |
| Former-active rebuild | 0.5 day | Rebuild second node using proven process |
| Dual-node/failover acceptance | 0.5 day | Restore and prove resilience |

A cautious end-to-end programme is therefore approximately **5-7 elapsed days**, largely because of the 24-48 hour passive observation period and 48 hour production soak. Hands-on engineering time is materially lower than the elapsed time.

## Rollback strategy

### Before SD overwrite

Normal reboot returns to CentOS.

### During RAM-rescue write/configuration

If rescue remains alive and Debian is not satisfactory, restore the previously captured full CentOS SD image over the VPN, sync, then reboot.

### After Debian successfully boots but before failover

The active CentOS node remains in service. Rebuild or restore the passive node without customer impact.

### After failover

If Debian production acceptance fails, restore service to the untouched CentOS active node, provided it has not yet been rebuilt.

### Second-node migration

Do not rebuild the original active CentOS node until the Debian node has completed production soak and rollback confidence is acceptable.

## Definition of done

- Both Raspberry Pi nodes run Debian 13.
- Required FreeSWITCH version/modules are installed and documented.
- All critical inbound/outbound call paths pass.
- RTP/DTMF/codec behaviour passes.
- Monitoring/logging/backup requirements pass.
- Active/passive failover and failback are demonstrated.
- Reboot tests pass on both nodes.
- No CentOS 7 production dependency remains.
- Runbook and test evidence are updated with actual site values.