# End-to-End Test Plan

## Purpose

Prove the migration mechanism, Debian image, FreeSWITCH workload and two-node failover before both CentOS systems are retired.

## Test stages

### T0 - Documentation and baseline

Pass criteria:

- both Pi identities recorded;
- active/passive roles confirmed;
- IP/MAC/gateway/DNS recorded;
- current FreeSWITCH version and module list captured;
- current config backed up;
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

On representative Raspberry Pi 3 hardware where available:

1. boot image;
2. confirm wired Ethernet;
3. confirm SSH;
4. confirm DHCP/static behaviour as designed;
5. confirm time sync;
6. confirm package manager works;
7. reboot twice;
8. confirm clean startup after each reboot.

### T3 - FreeSWITCH Debian test

Execute `FREESWITCH_TEST_PLAN.md`.

Minimum gate before production-site use:

- service starts;
- required modules load;
- SIP profiles start;
- test endpoint registration works;
- inbound/outbound call tests pass where a safe test path exists;
- two-way audio and DTMF pass;
- restart/reboot recovery passes.

### T4 - Passive-node preflight

Run `01-preflight.sh` and `03-rescue-readiness.sh`.

Pass criteria:

- expected Pi model/architecture;
- known target SD device;
- wired interface up;
- route to VPN router/default gateway;
- kexec capability present;
- enough RAM/disk for rescue preparation;
- no failed safety checks.

### T5 - Backup/restore confidence

Create and verify:

- configuration archive;
- package/service inventory;
- full off-node SD image.

Where a spare test device exists, restore the captured image to spare media and prove it is readable/bootable. If no spare media exists, at minimum verify compression/checksum and partition metadata from the stored image.

### T6 - RAM-rescue round trip

Test only on the passive node while the active CentOS node remains in service.

Sequence:

```text
CentOS
  -> load rescue
  -> enter RAM rescue
  -> reconnect over VPN/SSH
  -> verify network and SD visibility
  -> reboot without writing disk
  -> CentOS returns
```

Pass criteria:

- rescue reachable on expected IP/port;
- root filesystem is RAM/initramfs;
- SD card is visible but not used as rescue root;
- gateway reachable;
- rescue survives long enough for administration;
- normal reboot returns to CentOS and FreeSWITCH state is unchanged.

### T7 - Passive Debian migration

Use the exact image checksum already approved in T1-T3.

Pass criteria after write, before reboot:

- image write completes without error;
- `sync` completes;
- new partition table is readable;
- Debian root filesystem mounts;
- `/etc/os-release` reports Debian 13;
- node-specific hostname/network/SSH configuration present;
- no production secret omitted that is required for boot/service;
- boot files present.

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

At start, midpoint and end record:

- uptime;
- CPU/load;
- RAM/swap;
- filesystem usage;
- temperature where available;
- FreeSWITCH process state;
- SIP gateway/profile state;
- journal warnings/errors;
- monitoring/logging state.

Exercise test calls/routes throughout the window where possible.

### T10 - Controlled production failover

Preconditions:

- active CentOS node healthy;
- passive Debian node passed T0-T9;
- rollback procedure ready;
- configuration synchronised appropriately.

After failover immediately test critical inbound/outbound calls, RTP, DTMF and registration state.

Pass criteria:

- no critical call-path failure;
- no one-way audio;
- no persistent registration failure;
- node resource use remains acceptable.

### T11 - Production soak

Target observation: 48 hours.

Keep the former active CentOS node untouched and available for rollback throughout this window.

Pass criteria:

- no Severity 1/2 issue;
- stable registrations;
- expected call behaviour;
- acceptable CPU/RAM/storage/temperature;
- no repeated FreeSWITCH or kernel faults.

### T12 - Second-node rebuild

Repeat the proven process against the former active node while Debian carries production service.

### T13 - Resilience acceptance

With both nodes on Debian:

- validate active/passive roles;
- fail over intentionally;
- perform critical calls;
- reboot passive;
- restore passive and confirm readiness;
- reboot/fail active according to the supported mechanism;
- prove service survives as designed;
- confirm monitoring and logs distinguish both nodes.

## Evidence

Store for each test:

```text
Date/time:
Engineer:
Node:
Image SHA512:
Repository commit:
Test ID:
Result: PASS/FAIL/BLOCKED
Evidence/log location:
Notes:
Defect/reference:
```

## Timeline summary

A cautious testing sequence is expected to span roughly 5-7 elapsed days because the design deliberately includes a 24-48 hour passive soak and a further 48 hour production soak before the second node is rebuilt.

Suggested schedule:

- Day 1: baseline, image build and static tests
- Day 2: FreeSWITCH tests and rescue proof
- Day 3: passive-node rebuild and start passive soak
- Day 4: continue passive soak; resolve minor issues
- Day 5: controlled failover and production acceptance
- Days 5-7: production soak
- Day 7: second-node rebuild and dual-node resilience acceptance

If a Severity 1 or Severity 2 defect appears, the elapsed schedule pauses until it is resolved and the affected test stage is repeated.