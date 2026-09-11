# pios-rebuild

Remote, staged migration toolkit for rebuilding a two-node Raspberry Pi 3 FreeSWITCH site from CentOS 7 to Debian 13 without requiring an onsite engineer.

## Design principles

- The site VPN terminates on the router, so management access survives Pi reboots.
- There are two Raspberry Pi nodes. The passive node is rebuilt and proven first while the active CentOS node continues carrying service.
- The administration laptop is treated as part of the recovery design and must pass its own prerequisite check before either Pi is changed.
- Debian is not written until a RAM-rescue environment has been tested and a normal reboot back to CentOS has been proven.
- A full SD-card image and configuration backup are taken before destructive work.
- The existing FreeSWITCH configuration and runtime/module state are exported separately and copied off-node before rebuild.
- The Debian image is built and tested in advance with the required operational tooling and FreeSWITCH prerequisites.
- The exported FreeSWITCH configuration is restored onto Debian only after the required Debian FreeSWITCH packages/modules are present.
- FreeSWITCH on Debian 13 is a formal test gate before production failover.
- All destructive scripts fail closed and require explicit confirmation.

## Target sequence

1. Prepare and validate the administration laptop/workstation, VPN, SSH keys, local storage and toolchain.
2. Baseline both CentOS nodes and document the active/passive roles.
3. Export FreeSWITCH configuration/runtime state from both nodes and copy it to secure off-node storage.
4. Build a reproducible Debian 13 arm64 Raspberry Pi image with required tools and the chosen FreeSWITCH package set where practical.
5. Validate the exact image and FreeSWITCH in a non-production/lab test where possible.
6. Build and test the RAM-rescue mechanism on the passive node.
7. Rebuild the passive node to Debian 13.
8. Restore the passive node's exported FreeSWITCH configuration onto Debian and reconcile any module/package differences.
9. Validate Debian, FreeSWITCH, SIP, media, management and monitoring on the passive node.
10. Soak-test the passive node while the active CentOS node remains in service.
11. Perform a controlled service failover to the Debian node.
12. Validate production traffic and maintain a rollback window.
13. Once stable, rebuild the former active node using the same tested process and its own saved configuration.
14. Restore active/passive resilience and complete final acceptance testing.

## Repository layout

```text
.
├── README.md
├── .gitignore
├── .github/workflows/shellcheck.yml
├── config/
│   └── site.env.example
├── docs/
│   ├── ADMIN_LAPTOP_PREREQUISITES.md
│   ├── PROJECT_PLAN.md
│   ├── RUNBOOK.md
│   ├── TEST_PLAN.md
│   ├── IMAGE_BUILD.md
│   └── FREESWITCH_TEST_PLAN.md
└── scripts/
    ├── lib/common.sh
    ├── 00-admin-laptop-preflight.sh
    ├── 00-build-debian-image.sh
    ├── 01-preflight.sh
    ├── 02-backup-inventory.sh
    ├── 02a-export-freeswitch-config.sh
    ├── 03-rescue-readiness.sh
    ├── 04-load-rescue.sh
    ├── 05-enter-rescue.sh
    ├── 06-write-debian.sh
    ├── 07-validate-debian.sh
    ├── 07a-restore-freeswitch-config.sh
    └── 08-freeswitch-smoke-test.sh
```

## Administration laptop prerequisite

Read `docs/ADMIN_LAPTOP_PREREQUISITES.md` first. The workstation must have stable VPN connectivity, key-based SSH access to both Pi nodes, enough protected local storage for the rollback images and migration artifacts, the required CLI tools, and power/sleep settings suitable for long transfers.

Run the non-destructive workstation check before starting:

```bash
./scripts/00-admin-laptop-preflight.sh \
  --router <router-ip> \
  --active <user@active-pi-ip> \
  --passive <user@passive-pi-ip> \
  --min-free-gb <calculated-minimum>
```

## FreeSWITCH configuration migration

`02a-export-freeswitch-config.sh` captures the active configuration root, version, loaded-module information, Sofia/gateway state, package inventory and supplementary FreeSWITCH paths. The export can contain SIP credentials and other secrets, so it must be copied to secure storage and must never be committed to this repository.

After Debian and the required FreeSWITCH package/module set are installed, `07a-restore-freeswitch-config.sh` verifies the exported archive, backs up the fresh Debian configuration, stops FreeSWITCH and applies the exported configuration. It deliberately does **not** claim that the restored configuration is production-ready: `08-freeswitch-smoke-test.sh` and `docs/FREESWITCH_TEST_PLAN.md` are the acceptance gates.

## Important safety rule

Do not run `06-write-debian.sh` until the passive node has successfully completed the non-destructive rescue test and returned to CentOS. The write script requires an explicit `ERASE_CENTOS` confirmation and refuses to operate on a mounted target device.

## Current technical assumptions

- Raspberry Pi 3 family
- CentOS 7 current OS
- Debian 13 (Trixie) arm64 target
- Wired Ethernet for the migration path
- VPN terminates independently on the site router
- Two-node FreeSWITCH arrangement, with one node able to remain active while the passive node is rebuilt

All assumptions must be confirmed by `01-preflight.sh` before migration.