# pios-rebuild

Remote, staged migration toolkit for rebuilding a two-node Raspberry Pi 3 FreeSWITCH site from CentOS 7 to Debian 13 without requiring an onsite engineer.

## Design principles

- The site VPN terminates on the router, so management access survives Pi reboots.
- There are two Raspberry Pi nodes. The passive node is rebuilt and proven first while the active CentOS node continues carrying service.
- Debian is not written until a RAM-rescue environment has been tested and a normal reboot back to CentOS has been proven.
- A full SD-card image and configuration backup are taken before destructive work.
- The Debian image is built and tested in advance with the required operational tooling and FreeSWITCH prerequisites.
- FreeSWITCH on Debian 13 is a formal test gate before production failover.
- All destructive scripts fail closed and require explicit confirmation.

## Target sequence

1. Baseline both CentOS nodes and document the active/passive roles.
2. Build a reproducible Debian 13 arm64 Raspberry Pi image with required tools.
3. Validate the image and FreeSWITCH in a non-production/lab test where possible.
4. Build and test the RAM-rescue mechanism on the passive node.
5. Rebuild the passive node to Debian 13.
6. Validate Debian, FreeSWITCH, SIP, media, management and monitoring on the passive node.
7. Soak-test the passive node while the active CentOS node remains in service.
8. Perform a controlled service failover to the Debian node.
9. Validate production traffic and maintain a rollback window.
10. Once stable, rebuild the former active node using the same tested process.
11. Restore active/passive resilience and complete final acceptance testing.

## Repository layout

```text
.
├── README.md
├── config/
│   └── site.env.example
├── docs/
│   ├── PROJECT_PLAN.md
│   ├── RUNBOOK.md
│   ├── TEST_PLAN.md
│   ├── IMAGE_BUILD.md
│   └── FREESWITCH_TEST_PLAN.md
└── scripts/
    ├── lib/common.sh
    ├── 01-preflight.sh
    ├── 02-backup-inventory.sh
    ├── 03-rescue-readiness.sh
    ├── 04-load-rescue.sh
    ├── 05-enter-rescue.sh
    ├── 06-write-debian.sh
    ├── 07-validate-debian.sh
    └── 08-freeswitch-smoke-test.sh
```

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