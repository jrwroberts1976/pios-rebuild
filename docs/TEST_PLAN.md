# End-to-End Test Plan

## Purpose

Prove the migration mechanism, Debian image, FreeSWITCH workload and two-node failover before both CentOS systems are retired.

## Supported profiles

The test evidence must identify one of these profiles:

| Profile | Source | Target |
| --- | --- | --- |
| `PI3-CENTOS7` | Raspberry Pi 3 / CentOS 7 | Debian 13 arm64 |
| `PI4-CENTOS9` | Raspberry Pi 4 / CentOS 9 | Debian 13 arm64 |

A pass for one profile does **not** automatically approve the other. In particular, rescue boot, kernel/initramfs/DTB compatibility and exact-image boot testing are hardware/source-OS specific.

## Test stages

### T0 - Documentation and baseline

Pass criteria:

- migration profile selected and recorded;
- both Pi identities recorded;
- Raspberry Pi model and current CentOS version match the profile;
- active/passive roles confirmed;
- IP/MAC/gateway/DNS recorded;
- current FreeSWITCH version and module list captured;
- current configuration backed up;
- current failover method documented;
- critical call paths listed.

### T1 - Golden image static validation

Pass criteria:

- source Debian image checksum verified;
- output image checksum produced;
- output partition table readable;
- Debian 13 arm64 confirmed inside image;
- required admin/network/storage troubleshooting tools present;
- SSH installed/enabled;
- no production secret found in image;
- image manifest records source and repository revision.

### T2 - Golden image boot validation

Boot the **exact checksum-approved image** on representative hardware for every profile on which it will be used.

For `PI3-CENTOS7`, test on representative Raspberry Pi 3 hardware. For `PI4-CENTOS9`, test on representative Raspberry Pi 4 hardware.

Pass criteria:

1. image boots;
2. wired Ethernet works;
3. SSH works;
4. DHCP/static behaviour works as designed;
5. time sync works;
6. package manager works;
7. storage is detected correctly;
8. two reboot cycles complete cleanly.

### T3 - FreeSWITCH Debian test

Execute `FREESWITCH_TEST_PLAN.md` against the exact image/profile combination.

Minimum gate before production-site use:

- service starts;
- required modules load;
- SIP profiles start;
- test endpoint registration works;
- inbound/outbound call tests pass where a safe test path exists;
- two-way audio and DTMF pass;
- restart/reboot recovery passes.

### T4 - Passive-node preflight

Run `01-preflight.sh` and `03-rescue-readiness.sh` using the selected profile configuration.

Pass criteria:

- exact Pi model matches profile;
- architecture matches profile;
- CentOS ID/version matches profile;
- known whole SD-card device;
- wired interface up;
- route to VPN router/default gateway;
- kexec capability present;
- enough RAM/disk for rescue preparation;
- no failed safety checks.

### T5 - Backup/restore confidence

Create and verify:

- configuration archive;
- package/service inventory;
- FreeSWITCH export and checksum;
- full off-node 32 GB SD-card image and checksum.

Where a spare test device exists, restore the captured image to spare media and prove it is readable/bootable. If no spare media exists, at minimum verify checksum and partition metadata from the stored image.

### T6 - RAM-rescue round trip

Test only on the passive node while the active CentOS node remains in service.

For the selected profile, use the rescue build specifically validated for that Pi model/source CentOS version.

Sequence:

```text
Current CentOS
  -> load profile-specific rescue
  -> enter RAM rescue
  -> reconnect over VPN/SSH
  -> verify RAM-root, network and SD visibility
  -> reboot without writing disk
  -> same CentOS installation returns
```

Pass criteria:

- rescue reachable on expected IP/port;
- root filesystem is RAM/initramfs;
- SD card is visible but not used as rescue root;
- gateway reachable;
- rescue survives long enough for administration;
- normal reboot returns to the original CentOS version and FreeSWITCH state is unchanged.

### T7 - Passive Debian migration

Use the exact image checksum already approved in T1-T3 for the target hardware family.

Pass criteria after write, before reboot:

- image write completes without error;
- `sync` completes;
- new partition table is readable;
- Debian root filesystem mounts;
- `/etc/os-release` reports Debian 13;
- node-specific hostname/network/SSH configuration present;
- required boot files present.

### T8 - Passive first boot

Pass criteria:

- Pi reachable through router VPN;
- expected IP/MAC relation retained;
- SSH key login works;
- Debian 13 arm64 confirmed;
- no critical boot errors;
- system time correct;
- filesystem healthy;
- `apt update` works;
- FreeSWITCH starts or is ready for controlled configuration deployment.

### T9 - Passive functional/soak test

Target observation: 24-48 hours.

At start, midpoint and end record uptime, CPU/load, RAM/swap, filesystem usage, temperature, FreeSWITCH process state, SIP gateway/profile state, journal warnings/errors and monitoring/logging state. Exercise test calls/routes throughout the window where possible.

### T10 - Controlled production failover

Preconditions:

- active CentOS node healthy;
- passive Debian node passed T0-T9;
- rollback procedure ready;
- configuration synchronised appropriately.

After failover immediately test critical inbound/outbound calls, RTP, DTMF and registration state.

### T11 - Production soak

Target observation: 48 hours. Keep the former active CentOS node untouched and available for rollback throughout this window.

Pass criteria: no Severity 1/2 issue, stable registrations, expected call behaviour, acceptable resources and no repeated FreeSWITCH/kernel faults.

### T12 - Second-node rebuild

Repeat the proven process against the former active node while Debian carries production service. The same migration profile must still match that node unless preflight explicitly proves otherwise.

### T13 - Resilience acceptance

With both nodes on Debian, validate roles, deliberate failover/failback, critical calls, individual reboot behaviour and monitoring/logging identity.

## Additional Pi 4 / CentOS 9 tests

For `PI4-CENTOS9`, explicitly record:

- Pi 4 model string;
- CentOS 9 kernel and boot layout;
- Pi 4 Ethernet driver availability in rescue;
- Pi 4 SD/MMC visibility in rescue;
- DTB used by the rescue build;
- successful `CentOS 9 -> RAM rescue -> CentOS 9` round trip;
- successful boot of the exact Debian 13 image on Pi 4.

Do not inherit those results from a Pi 3 test run.

## Evidence

Store for each test:

```text
Date/time:
Engineer:
Migration profile:
Node:
Pi model:
Source OS/version:
Image SHA512:
Rescue build ID/checksum:
Repository commit:
Test ID:
Result: PASS/FAIL/BLOCKED
Evidence/log location:
Notes:
Defect/reference:
```

## Timeline summary

A cautious sequence is expected to span roughly 5-7 elapsed days because it deliberately includes a 24-48 hour passive soak and a further 48 hour production soak before the second node is rebuilt.

For the first node of a newly proven profile, book **3-4 hours** for the hands-on migration. Once the profile is proven, a later node should normally take about **1.5-2.5 hours**, with 2-3 hours a sensible working allowance.

If a Severity 1 or Severity 2 defect appears, the schedule pauses until it is resolved and the affected test stage is repeated.
