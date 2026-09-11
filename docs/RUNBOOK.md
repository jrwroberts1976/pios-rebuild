# Remote Rebuild Runbook

## Scope

This runbook covers the staged rebuild of a two-node Raspberry Pi 3 FreeSWITCH site from CentOS 7 to Debian 13 over a router-hosted VPN with no onsite engineer.

## Safety model

- The VPN terminates on the router and is independent of both Pi nodes.
- The passive node is rebuilt first while the active CentOS node continues service.
- The administration laptop is part of the recovery design and must remain available throughout backup, rescue, image streaming and rollback.
- The existing CentOS SD card is not overwritten until the RAM-rescue path has been proven non-destructively.
- A full block-level CentOS image and a separate FreeSWITCH configuration export are retained off-node.
- The original active CentOS node is not rebuilt until the Debian node has passed production soak.

## Record site values

```text
ACTIVE_NODE_HOSTNAME=
ACTIVE_NODE_IP=
ACTIVE_NODE_MAC=
PASSIVE_NODE_HOSTNAME=
PASSIVE_NODE_IP=
PASSIVE_NODE_MAC=
VPN_ROUTER_IP=
```

Do not infer active/passive state from hostname alone. Confirm actual service state.

---

# Phase -1 - Administration laptop prerequisite

Read `ADMIN_LAPTOP_PREREQUISITES.md`.

The laptop/workstation must have:

- stable VPN access to the site router;
- key-based SSH access to both Pi nodes;
- sufficient protected local storage for the CentOS disk images, Debian image, FreeSWITCH exports and evidence;
- required CLI tools including SSH, rsync, Git, checksum utilities, compression tools, `dd` and `pv`;
- mains power;
- automatic sleep/hibernate disabled during the maintenance activity;
- the repository checked out at a known commit;
- the verified rollback images immediately accessible.

Run:

```bash
./scripts/00-admin-laptop-preflight.sh \
  --router <router-ip> \
  --active <user@active-pi-ip> \
  --passive <user@passive-pi-ip> \
  --min-free-gb <calculated-minimum>
```

**GO gate:** `ADMIN_LAPTOP_PREFLIGHT=PASS`, plus manual power/sleep/VPN-reconnect gates confirmed.

---

# Phase 0 - Build and test the Debian image

Before changing either production Pi:

1. obtain the official Debian 13 Raspberry Pi arm64 image and verify its official checksum;
2. use `scripts/00-build-debian-image.sh` and `IMAGE_BUILD.md` to produce the project golden image;
3. record the output SHA512 and repository commit;
4. boot the exact output image on representative Pi 3 hardware where available;
5. install/test the selected FreeSWITCH version and required modules;
6. complete the relevant tests in `FREESWITCH_TEST_PLAN.md`;
7. retain the exact approved image artifact used in testing.

**GO gate:** approved Debian image checksum and FreeSWITCH test evidence exist.

---

# Phase 1 - Baseline both production nodes

Create a protected local site configuration from `config/site.env.example`. Do not commit production secrets.

On **both** CentOS nodes:

```bash
sudo bash scripts/01-preflight.sh
sudo bash scripts/02-backup-inventory.sh
sudo bash scripts/02a-export-freeswitch-config.sh
```

Copy all generated inventory and FreeSWITCH export artifacts to the administration laptop/approved secure storage.

## FreeSWITCH export requirement

The FreeSWITCH export is separate from the generic OS backup because it will be deliberately restored onto Debian.

It captures, where available:

- full FreeSWITCH configuration tree;
- installed/runtime FreeSWITCH version;
- loaded-module state;
- Sofia profile state;
- gateway state;
- installed FreeSWITCH package list;
- supplementary script/data paths;
- checksums.

The archive may contain SIP credentials, TLS material and event-socket/provider passwords. Treat it as sensitive and never commit it to Git.

Verify the copied archive checksum on the laptop.

**GO gate:** both node inventories and both verified FreeSWITCH exports are safely off-node.

---

# Phase 2 - Passive-node full disk backup

Take a full block image of the passive Pi SD card and save it on the administration laptop or another approved system.

Example from the admin laptop:

```bash
ssh root@PASSIVE_NODE 'dd if=/dev/mmcblk0 bs=4M status=none' \
  | gzip -1 > passive-centos7-before-debian.img.gz

gzip -t passive-centos7-before-debian.img.gz
sha256sum passive-centos7-before-debian.img.gz \
  > passive-centos7-before-debian.img.gz.sha256
```

Use the actual SSH user and confirmed target device from preflight.

A live block image is a disaster-recovery copy. It does not replace the application/configuration export from Phase 1.

**GO gate:** full off-node image exists and compression/checksum verification passes.

---

# Phase 3 - Passive rescue readiness

Run on the passive node:

```bash
sudo bash scripts/03-rescue-readiness.sh
```

The gate checks:

- Raspberry Pi identity;
- architecture/kernel;
- target SD device;
- wired network interface/default route;
- `kexec` userspace tool;
- kernel `CONFIG_KEXEC` capability;
- candidate kernel/initramfs/DTB files.

If it reports:

```text
RESCUE_READY=NO
```

stop. Do not replace the SD card remotely using an improvised method.

---

# Phase 4 - Build the RAM rescue environment

The rescue environment must contain enough to operate independently of the SD card:

- known-compatible kernel/modules;
- RAM-root initramfs;
- Pi 3 Ethernet and SD/MMC support;
- network tools and DHCP/static configuration;
- Dropbear or equivalent SSH server;
- approved SSH public key;
- `lsblk`, `mount`, `umount`, `dd`, `fdisk`/`parted`;
- checksum/decompression tools;
- watchdog support where proven.

The exact rescue build depends on the CentOS kernel and boot layout found in Phase 3. Do not use an untested generic rescue image.

---

# Phase 5 - Load rescue without executing it

After the exact kernel/initramfs/DTB arguments are reviewed:

```bash
sudo bash scripts/04-load-rescue.sh
```

This loads the rescue into the `kexec` slot only.

Check:

```bash
cat /sys/kernel/kexec_loaded 2>/dev/null || true
```

Expected where supported:

```text
1
```

If anything is unexpected, unload the kexec image and stop.

---

# Phase 6 - Non-destructive rescue proof

Enter rescue:

```bash
sudo bash scripts/05-enter-rescue.sh ENTER_RESCUE
```

The CentOS SSH session will end.

Reconnect from the admin laptop over the router VPN to the rescue SSH port, normally:

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

Required result:

- rescue root is RAM/initramfs;
- Pi Ethernet works;
- VPN path reaches the rescue SSH service;
- SD card is visible;
- the SD card is not the rescue root filesystem.

**Do not write Debian during this first rescue test.**

Reboot normally:

```bash
sync
reboot -f
```

Reconnect to CentOS on its normal SSH port and confirm FreeSWITCH/service state.

**GO gate:** `CentOS -> RAM rescue -> CentOS` succeeds over the VPN.

---

# Phase 7 - Real passive-node migration

Repeat the now-proven rescue process and reconnect to RAM rescue.

Before destructive work, re-confirm:

- VPN stable;
- correct passive node/IP/MAC;
- target device correct;
- target partitions unmounted;
- approved Debian image checksum matches the tested artifact;
- full CentOS disk backup remains available on the admin laptop;
- passive node FreeSWITCH export remains available on the admin laptop.

## Write the approved Debian image

If the image is made locally available to rescue:

```bash
sudo bash scripts/06-write-debian.sh \
  --target /dev/mmcblk0 \
  --image /path/to/approved-debian.img.xz \
  --confirm ERASE_CENTOS
```

Alternatively, stream a **previously checksum-verified** raw image from the administration laptop into the rescue writer's `--stdin-raw` mode. Do not buffer a multi-gigabyte raw image in Pi RAM.

The writer requires:

- literal destructive confirmation;
- expected whole-disk target;
- target unmounted;
- rescue root detected as RAM-resident;
- approved checksum for local-image mode.

After the write completes, **do not reboot yet**.

Reread the partition table, mount the new Debian root/boot filesystems and apply node-specific:

- hostname;
- network configuration/DHCP expectations;
- SSH authorized key;
- required first-boot configuration.

Inspect `/etc/os-release`, boot files and filesystem configuration before rebooting.

---

# Phase 8 - First Debian boot and OS validation

When offline checks pass:

```bash
sync
reboot
```

Reconnect through the router VPN.

Run:

```bash
sudo bash scripts/07-validate-debian.sh
```

Required result:

```text
DEBIAN_VALIDATION=PASS
```

If Debian is unhealthy but reachable, troubleshoot/rebuild the passive node while the CentOS active node continues production service.

---

# Phase 9 - Restore FreeSWITCH configuration

Before applying the old configuration, ensure Debian has the required FreeSWITCH packages/modules identified during the baseline and image tests.

Copy the passive node's verified FreeSWITCH export from the administration laptop to a protected temporary location on Debian.

Run:

```bash
sudo bash scripts/07a-restore-freeswitch-config.sh \
  --archive /path/to/freeswitch-config.tgz \
  --confirm APPLY_FREESWITCH_CONFIG
```

The restore script:

1. verifies the export checksum sidecar;
2. verifies the OS is the expected Debian release;
3. identifies/uses the Debian FreeSWITCH configuration destination;
4. backs up the fresh Debian configuration;
5. stops FreeSWITCH if present;
6. overlays the exported configuration;
7. normalises ownership/permissions for the Debian service account;
8. leaves service acceptance to the next test stage.

Do not assume CentOS module names/packages map one-for-one to Debian. Reconcile missing/deprecated modules before failover.

Then run:

```bash
sudo bash scripts/08-freeswitch-smoke-test.sh --start
```

and complete `FREESWITCH_TEST_PLAN.md`.

---

# Phase 10 - Passive-node soak

Keep the Debian node passive for **24-48 hours** while the original CentOS node remains active.

During the soak review:

- FreeSWITCH uptime;
- profiles/gateways/registrations;
- CPU/RAM/swap;
- SD-card/storage health indicators;
- temperature;
- logs;
- time synchronisation;
- monitoring;
- test SIP/RTP call paths where possible.

Do not rebuild the active CentOS node yet.

---

# Phase 11 - Controlled production failover

Preconditions:

- passive Debian node passed OS and FreeSWITCH tests;
- passive soak completed;
- active CentOS node is healthy;
- current config/export backups exist;
- rollback method is ready.

Use the site's existing active/passive mechanism to move production service to Debian.

Immediately test critical:

- inbound calls;
- outbound calls;
- two-way audio;
- DTMF;
- caller ID;
- SIP registration/gateway state;
- application-specific call flows.

If a Severity 1 or Severity 2 issue appears, fail service back to the untouched CentOS node.

---

# Phase 12 - Production soak

Operate the Debian node as active for approximately **48 hours**.

Keep the original CentOS node unchanged and available for rollback throughout this period.

Only after the production soak passes is the second rebuild approved.

---

# Phase 13 - Rebuild the former active node

Before rebuilding the second node, re-export its FreeSWITCH configuration if production/configuration may have changed since the original baseline:

```bash
sudo bash scripts/02a-export-freeswitch-config.sh
```

Copy/verify it off-node.

Then repeat the proven:

```text
preflight
-> full disk backup
-> rescue readiness
-> rescue round-trip proof if required by change policy
-> RAM rescue
-> Debian write
-> Debian validation
-> FreeSWITCH package/module reconciliation
-> FreeSWITCH config restore
-> FreeSWITCH tests
```

Configure this node for its intended standby/passive role.

---

# Phase 14 - Dual-node resilience acceptance

With both nodes on Debian 13:

- validate unique node identity/IPs;
- confirm normal active/passive roles;
- deliberately fail over;
- repeat critical inbound/outbound call tests;
- fail back where supported;
- reboot each node individually while the other carries service;
- confirm monitoring/logging identifies both nodes correctly.

---

# Emergency rollback matrix

| State | Rollback |
| --- | --- |
| Before rescue | No OS change required |
| Rescue loaded but not executed | Unload `kexec` or reboot normally |
| Rescue running, SD untouched | Reboot to CentOS |
| Debian write complete, rescue still alive | Stream verified CentOS full-disk image back to SD, `sync`, reboot |
| Debian booted, before failover | Active CentOS node continues service; repair/rebuild passive |
| FreeSWITCH config restore fails | Restore the fresh-Debian FreeSWITCH backup and reconcile modules/config |
| Debian active after failover | Fail service back to untouched CentOS node |
| Both nodes already Debian | Use retained system/config backups and documented service recovery procedure |

# Absolute stop conditions

Stop rather than improvise if:

- admin-laptop prerequisite gate fails;
- VPN/router connectivity is unstable;
- active/passive role is uncertain;
- SSH access to either node is unreliable before starting;
- target disk identity is uncertain;
- full CentOS backup is unavailable/corrupt;
- FreeSWITCH export is unavailable/corrupt;
- `kexec`/rescue proof has not passed;
- rescue cannot be reached through the VPN;
- Debian image checksum differs from the tested artifact;
- FreeSWITCH Debian testing has an unresolved Severity 1/2 defect;
- original active CentOS node is unavailable before Debian production failover.