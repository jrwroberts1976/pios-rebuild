# Remote Rebuild Runbook

## Scope

This runbook covers the staged rebuild of a two-node Raspberry Pi 3 FreeSWITCH site from CentOS 7 to Debian 13 over a router-hosted VPN with no onsite engineer.

## Safety model

The passive node is always rebuilt first. The active CentOS node remains in service and untouched until the Debian node has passed testing and production soak.

The remote rebuild uses a RAM-rescue environment so the SD card can be unmounted before Debian is written. A full block-level backup is taken off-node first.

## Roles

Record before starting:

```text
ACTIVE_NODE_HOSTNAME=
ACTIVE_NODE_IP=
ACTIVE_NODE_MAC=
PASSIVE_NODE_HOSTNAME=
PASSIVE_NODE_IP=
PASSIVE_NODE_MAC=
VPN_ROUTER_IP=
```

Do not assume which node is passive based on hostname alone. Confirm actual service state.

## Phase 0 - Build/test prerequisite

Before touching either production Pi:

1. build the Debian 13 golden image described in `IMAGE_BUILD.md`;
2. record its SHA512 checksum;
3. boot/test the exact image on representative hardware if available;
4. install/test the required FreeSWITCH version and modules;
5. complete the relevant tests in `FREESWITCH_TEST_PLAN.md`;
6. retain the exact approved image artifact for production use.

**GO gate:** approved Debian image and FreeSWITCH test evidence exist.

## Phase 1 - Baseline both production nodes

Copy `config/site.env.example` to a local protected `site.env` and populate known values. Do not commit production secrets.

On each node run:

```bash
sudo ./scripts/01-preflight.sh
sudo ./scripts/02-backup-inventory.sh
```

Copy the generated inventory/config archives away from the Pi.

Capture current FreeSWITCH state as described in `FREESWITCH_TEST_PLAN.md`.

**GO gate:** both nodes have current inventories and FreeSWITCH configuration backups.

## Phase 2 - Passive-node full disk backup

Take a full block image of the passive node's SD card and store it on an administration system, not on the Pi's SD card.

Example pattern from an administration host:

```bash
ssh root@PASSIVE_NODE 'dd if=/dev/mmcblk0 bs=4M status=none' \
  | gzip -1 > passive-centos7-before-debian.img.gz

gzip -t passive-centos7-before-debian.img.gz
sha256sum passive-centos7-before-debian.img.gz \
  > passive-centos7-before-debian.img.gz.sha256
```

Adjust SSH user/device only after confirming the actual environment. A live block image is a disaster-recovery safety copy, not a replacement for an application-consistent FreeSWITCH/configuration backup.

**GO gate:** off-node image exists and checksum/integrity test passes.

## Phase 3 - Rescue readiness

On the passive node:

```bash
sudo ./scripts/03-rescue-readiness.sh
```

This checks:

- Pi identity;
- kernel and architecture;
- `CONFIG_KEXEC` support;
- current root device;
- target SD device;
- wired network state;
- available boot kernel/initramfs/DTB information;
- required rescue tooling.

If it reports `RESCUE_READY=NO`, stop.

## Phase 4 - Build RAM rescue

The rescue image must contain:

- the known-working kernel/modules or a separately proven compatible kernel;
- initramfs root;
- network tooling;
- DHCP/static fallback configuration;
- Dropbear or equivalent SSH server;
- approved public SSH key;
- disk inspection/write tools;
- checksum/decompression tools.

The exact rescue-build implementation depends on the CentOS kernel and initramfs tooling discovered by Phase 3. Do not use a generic rescue image without proving Pi 3 Ethernet and SD support.

## Phase 5 - Load rescue without entering it

After the rescue image and exact kernel/DTB arguments have been reviewed:

```bash
sudo ./scripts/04-load-rescue.sh
```

The script loads the rescue into the kexec slot only. It does not execute it.

Review:

```bash
cat /sys/kernel/kexec_loaded 2>/dev/null || true
```

If anything is unexpected, unload with the appropriate `kexec -u` command and stop.

## Phase 6 - Non-destructive rescue test

Enter rescue only after the load stage passes:

```bash
sudo ./scripts/05-enter-rescue.sh ENTER_RESCUE
```

The existing CentOS SSH session will disappear.

Reconnect to the RAM rescue on its configured alternate SSH port, for example:

```bash
ssh -p 2222 root@PASSIVE_NODE_IP
```

Inside rescue verify:

```bash
findmnt /
mount
ip -br addr
ip route
ping -c 3 VPN_ROUTER_IP
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL
fdisk -l /dev/mmcblk0
```

The SD card must not be the rescue root filesystem.

Do **not** write Debian on this first rescue test.

Reboot normally:

```bash
sync
reboot -f
```

Confirm CentOS returns on its normal SSH port.

**GO gate:** CentOS -> RAM rescue -> CentOS round trip passes over the VPN.

## Phase 7 - Real passive-node migration

Repeat the already-proven process and reconnect to RAM rescue.

Verify again:

- VPN path remains available;
- expected node MAC/IP is present;
- target device is correct;
- target partitions are not mounted;
- approved Debian image checksum matches test evidence;
- full CentOS backup remains available off-node.

Stream the approved image from the administration system to rescue, or make the verified image locally available to rescue, then execute the guarded writer:

```bash
sudo ./scripts/06-write-debian.sh \
  --target /dev/mmcblk0 \
  --image /path/to/approved-debian.img.xz \
  --confirm ERASE_CENTOS
```

If streaming rather than staging locally, follow the streaming method documented alongside the final site-specific implementation. Never buffer a multi-gigabyte raw disk image in Pi RAM.

After the write, **do not reboot immediately**.

Reread the partition table and inspect/mount the new Debian filesystem. Apply node-specific hostname, SSH key, network and FreeSWITCH configuration.

Validate the offline Debian installation.

## Phase 8 - First Debian boot

Only when offline checks pass:

```bash
sync
reboot
```

Reconnect through the router VPN using the expected reserved IP.

Run:

```bash
sudo ./scripts/07-validate-debian.sh
sudo ./scripts/08-freeswitch-smoke-test.sh
```

If Debian is unhealthy but still remotely reachable, diagnose or rebuild the passive node while the CentOS active node continues carrying service.

## Phase 9 - Passive soak

Keep the Debian node passive for 24-48 hours.

Run scheduled/manual checks from `TEST_PLAN.md` and exercise test calls/routes where possible.

Do not migrate the active node.

## Phase 10 - Controlled failover

Confirm:

- current config on both nodes is backed up;
- Debian passive tests pass;
- rollback to CentOS active is ready;
- SIP/trunk/provider behaviour for failover is understood.

Fail service to the Debian node using the site's actual failover mechanism.

Immediately run critical call tests.

If a Severity 1/2 issue appears, return service to the untouched CentOS node.

## Phase 11 - Production soak

Run the Debian node as active for approximately 48 hours.

Only after this soak passes is the former CentOS active node approved for rebuild.

## Phase 12 - Rebuild former active node

Repeat Phases 1-8 against the second node using the exact same approved image and scripts.

Configure it as the passive/standby node.

## Phase 13 - Dual-node acceptance

Test:

- active-to-passive failover;
- passive-to-active failback where applicable;
- node-specific IP/identity;
- inbound/outbound calling on each service role;
- reboot of one node while the other remains active;
- monitoring/logging for both nodes.

## Emergency rollback matrix

| State | Rollback |
| --- | --- |
| Before first rescue | No change required |
| Rescue loaded but not executed | Unload kexec or reboot normally |
| Rescue running, SD untouched | Reboot to CentOS |
| Debian write complete, rescue still running | Restore full CentOS disk image, sync, reboot |
| Debian booted, before failover | Active CentOS node continues service; repair/rebuild passive |
| Debian active after failover | Fail service back to untouched CentOS node |
| Both nodes already Debian | Restore using retained image/config backups and documented service procedure |

## Absolute stop conditions

Stop rather than improvise if:

- VPN/router access is unstable;
- the active/passive role is uncertain;
- target disk identity is uncertain;
- full backup is unavailable or corrupt;
- `kexec`/rescue proof has not passed;
- rescue cannot be reached over VPN;
- Debian image checksum differs from the tested artifact;
- FreeSWITCH Debian tests have unresolved Severity 1/2 issues;
- the original active CentOS node is unavailable before the passive-node production failover.