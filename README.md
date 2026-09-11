# pios-rebuild

Remote, staged migration toolkit for rebuilding two-node Raspberry Pi FreeSWITCH sites to Debian 13 without requiring an onsite engineer.

> [!WARNING]
> **Engineering status: NOT YET END-TO-END TESTED.**
>
> This repository currently documents and implements a proposed migration method. The complete process — including the profile-specific RAM-rescue path, full SD-card rollback image, destructive Debian write, first boot, FreeSWITCH restoration and recovery/rollback path — has **not yet been proven end to end on the target production estate**.
>
> **Do not use this process for a production migration until the applicable Pi profile has completed the documented lab/passive-node tests and the exact release approach has received peer technical approval.** Peer approval should cover the release commit, runbook, rescue build, Debian image, FreeSWITCH migration method, safety gates and rollback plan. Approval must not be inferred simply because the scripts run successfully.

## Supported migration profiles

| Profile | Current platform | Target platform |
| --- | --- | --- |
| `PI3-CENTOS7` | Raspberry Pi 3, CentOS 7 | Debian 13 arm64 |
| `PI4-CENTOS9` | Raspberry Pi 4, CentOS 9 | Debian 13 arm64 |

The migration sequence is shared, but **hardware/OS-specific rescue builds are not interchangeable**. Pi 4 / CentOS 9 must have its own proven rescue kernel/initramfs/DTB combination and exact Debian-image boot test. See `docs/PI4_CENTOS9.md`.

## Design principles

- The site VPN terminates on the router, so management access survives Pi reboots.
- There are two Raspberry Pi nodes. The passive node is rebuilt and proven first while the active CentOS node continues carrying service.
- The administration laptop is treated as part of the recovery design and must pass its own prerequisite check before either Pi is changed.
- Debian is not written until a RAM-rescue environment appropriate to the selected model/source-OS profile has been tested and a normal reboot back to CentOS has been proven.
- A full SD-card image and configuration backup are taken before destructive work.
- The existing FreeSWITCH configuration and runtime/module state are exported separately and copied off-node before rebuild.
- The Debian image is built and tested in advance with the required operational tooling and FreeSWITCH prerequisites.
- The exported FreeSWITCH configuration is restored onto Debian only after the required Debian FreeSWITCH packages/modules are present.
- FreeSWITCH on Debian 13 is a formal test gate before production failover.
- All destructive scripts fail closed and require explicit confirmation.
- A Windows administration laptop can use the PowerShell controller scripts while low-level Pi operations remain Linux/bash inside the target or RAM rescue environment.

## Target sequence

1. Select and record the migration profile (`PI3-CENTOS7` or `PI4-CENTOS9`).
2. Prepare and validate the administration laptop/workstation, VPN, SSH keys, local storage and toolchain.
3. Baseline both CentOS nodes and document the active/passive roles.
4. Export FreeSWITCH configuration/runtime state from both nodes and copy it to secure off-node storage.
5. Build a reproducible Debian 13 arm64 Raspberry Pi image with required tools and the chosen FreeSWITCH package set where practical.
6. Validate the exact image and FreeSWITCH on representative hardware for the selected profile.
7. Build and test the RAM-rescue mechanism on the passive node for the selected hardware/OS profile.
8. Rebuild the passive node to Debian 13.
9. Restore the passive node's exported FreeSWITCH configuration onto Debian and reconcile any module/package differences.
10. Validate Debian, FreeSWITCH, SIP, media, management and monitoring on the passive node.
11. Soak-test the passive node while the active CentOS node remains in service.
12. Perform a controlled service failover to the Debian node.
13. Validate production traffic and maintain a rollback window.
14. Once stable, rebuild the former active node using the same tested process and its own saved configuration.
15. Restore active/passive resilience and complete final acceptance testing.

## Estimated migration duration

For a Raspberry Pi using a 32 GB SD card, allow approximately **2-3 hours per Pi once the process has been proven**. The first passive-node migration should be given a larger **3-4 hour window** because the RAM-rescue method, Debian image, FreeSWITCH restoration and validation steps are being proven for that profile. Once that migration has passed its acceptance tests, the second Pi should normally take approximately **1.5-2.5 hours** if no unexpected issues are found.

The largest timing variables are the speed of the full 32 GB rollback-image transfer, SD-card write speed, FreeSWITCH package/configuration reconciliation and the amount of functional testing required. These figures are hands-on migration estimates and do not include the planned soak periods before and after production failover.

## Repository layout

```text
.
├── README.md                                  # project overview and operator entry point
├── higher-risk-fully-automated-script.md      # design for the future one-button workflow
├── .gitignore
├── .github/
│   └── workflows/
│       └── shellcheck.yml                     # Linux shell validation
├── config/
│   ├── site.env.example                       # PI3-CENTOS7 profile template
│   └── site-pi4-centos9.env.example           # PI4-CENTOS9 profile template
├── docs/
│   ├── ADMIN_LAPTOP_PREREQUISITES.md          # workstation/VPN/storage prerequisites
│   ├── PROJECT_PLAN.md                        # staged migration project plan
│   ├── RUNBOOK.md                             # detailed engineering runbook
│   ├── TEST_PLAN.md                           # end-to-end acceptance tests
│   ├── IMAGE_BUILD.md                         # Debian 13 golden-image build
│   ├── FREESWITCH_TEST_PLAN.md                # telephony acceptance tests
│   ├── PI4_CENTOS9.md                         # Pi 4 / CentOS 9 profile details
│   ├── POWERSHELL.md                          # Windows/PowerShell operating guide
│   ├── POWERSHELL_VISUAL.md                   # visual PowerShell walkthrough
│   ├── RELEASE_DAY.md                         # on-the-day change procedure
│   ├── RELEASE_RECORD.md                      # electronic release-record guidance
│   ├── RELEASE_RECORD_TEMPLATE.md             # generated-record template
│   └── images/                                # documentation screenshots/diagrams
├── scripts/
│   ├── lib/
│   │   └── common.sh                          # shared Linux safety functions
│   ├── 00-admin-laptop-preflight.sh
│   ├── 00-build-debian-image.sh
│   ├── 01-preflight.sh
│   ├── 02-backup-inventory.sh
│   ├── 02a-export-freeswitch-config.sh
│   ├── 03-rescue-readiness.sh
│   ├── 04-load-rescue.sh
│   ├── 05-enter-rescue.sh
│   ├── 06-write-debian.sh
│   ├── 07-validate-debian.sh
│   ├── 07a-restore-freeswitch-config.sh
│   ├── 08-freeswitch-smoke-test.sh
│   └── powershell/
│       ├── 00-setup-environment.ps1           # clone/pull/pin release commit
│       ├── 00-admin-laptop-preflight.ps1      # Windows readiness/VPN/storage check
│       ├── 01-create-release-record.ps1       # detect target/profile and create release record
│       ├── 02-full-sd-backup.ps1              # raw 32 GB rollback image over SSH
│       ├── 05-connect-rescue.ps1              # reconnect to RAM rescue
│       ├── Copy-PiosArtifacts.ps1             # copy/checksum migration evidence
│       └── Invoke-PiosRemoteStage.ps1         # stage/run Linux scripts over SSH
└── releases/                                  # generated locally at runtime; ignored by Git
    └── <change-reference>-<timestamp>.md       # live electronic release evidence
```

`releases/` is created locally by the release-record workflow and is intentionally excluded by `.gitignore`; it is shown above because it is part of the operator's working layout even though it is not committed to the repository.

The higher-risk one-button workflow is currently a **design only** in `higher-risk-fully-automated-script.md`. `ONE-BUTTON-REBUILD.cmd` and `Invoke-FullyAutomatedRebuild.ps1` are therefore not shown as tracked files until those implementations actually exist.

## Windows / PowerShell operation

Windows PowerShell/PowerShell 7 is supported as the administration-laptop control shell. Read `docs/POWERSHELL.md` for the end-to-end command sequence and `docs/POWERSHELL_VISUAL.md` for the visual walkthrough.

The PowerShell scripts do not replace the Linux safety checks. They stage and invoke the tested Linux scripts over SSH, retrieve evidence and take rollback images. The actual RAM-rescue and SD-card write checks remain on the Raspberry Pi/rescue environment so they can directly verify the hardware, mounted filesystems and target block device.

### Set up or refresh the release checkout

If the repository has not been cloned yet:

```powershell
$RepoPath = Join-Path $HOME 'pios-rebuild'
git clone https://github.com/jrwroberts1976/pios-rebuild.git $RepoPath
Set-Location $RepoPath
```

If it already exists:

```powershell
$RepoPath = Join-Path $HOME 'pios-rebuild'
Set-Location $RepoPath
git status --short
git fetch origin --prune
git checkout main
git pull --ff-only origin main
git log -1 --oneline
$ReleaseCommit = (git rev-parse HEAD).Trim()
Write-Host "Release commit: $ReleaseCommit"
```

The working tree must be clean before the pull. After recording the release commit, do not run another `git pull` during the migration.

Once the repository already exists, the same preparation can be performed with:

```powershell
pwsh .\scripts\powershell\00-setup-environment.ps1 `
  -RepoPath $RepoPath `
  -Branch main
```

Required result:

```text
ENVIRONMENT_SETUP=PASS
```

### Create the electronic release record

You do **not** need to print the release-day document. After pinning the Git commit, generate a dated local Markdown record and keep it open while you work.

For Pi 4 / CentOS 9:

```powershell
pwsh .\scripts\powershell\01-create-release-record.ps1 `
  -Profile PI4-CENTOS9 `
  -Target <user@passive-pi-ip> `
  -Active <user@active-pi-ip> `
  -Router <router-ip> `
  -Site '<site-name>' `
  -ChangeReference '<change-reference>' `
  -SdDevice /dev/mmcblk0 `
  -DebianImage 'C:\pios-images\pios-debian13-arm64.img.xz'
```

The script performs read-only SSH discovery, records the exact Git commit, target/active host identity, Pi model, current OS, architecture, MAC, SD capacity and Debian image SHA512, and checks that the selected migration profile matches the target. A mismatch creates the evidence file but returns `RELEASE_PROFILE_GATE=NO-GO`.

Generated records are written under `releases/` by default and are ignored by Git. See `docs/RELEASE_RECORD.md` and `docs/RELEASE_RECORD_TEMPLATE.md`.

Run the Windows preflight with:

```powershell
pwsh .\scripts\powershell\00-admin-laptop-preflight.ps1 `
  -Router <router-ip> `
  -Active <user@active-pi-ip> `
  -Passive <user@passive-pi-ip> `
  -MinFreeGB 80
```

For two 32 GB SD cards, **80 GB free on the laptop is the recommended working minimum** when retaining both full raw rollback images plus the Debian image, configuration exports, checksums and evidence.

## Release-day document

Use `docs/RELEASE_DAY.md` as the operator's **on-the-day change procedure**. Use the generated file under `releases/` as the live electronic evidence record. Record the selected migration profile, Pi model and current CentOS version at the start of the change. A profile mismatch is a NO-GO.

It contains Git clone/fetch/pull and exact release-commit pinning, change-record fields, the 3-4 hour first-passive-node window, PowerShell commands in release order, GO/NO-GO gates, destructive-change checkpoint, rollback decisions and a separate production-failover release after soak.

The full `docs/RUNBOOK.md` remains the engineering reference. `RELEASE_DAY.md` is the procedure followed during the maintenance window; the generated release record is the evidence you update as you go.

## Administration laptop prerequisite

Read `docs/ADMIN_LAPTOP_PREREQUISITES.md` first. The workstation must have stable VPN connectivity, key-based SSH access to both Pi nodes, enough protected local storage for the rollback images and migration artifacts, the required CLI tools, and power/sleep settings suitable for long transfers.

Linux/WSL example:

```bash
./scripts/00-admin-laptop-preflight.sh \
  --router <router-ip> \
  --active <user@active-pi-ip> \
  --passive <user@passive-pi-ip> \
  --min-free-gb 80
```

PowerShell example:

```powershell
pwsh .\scripts\powershell\00-admin-laptop-preflight.ps1 `
  -Router <router-ip> `
  -Active <user@active-pi-ip> `
  -Passive <user@passive-pi-ip> `
  -MinFreeGB 80
```

## FreeSWITCH configuration migration

`02a-export-freeswitch-config.sh` captures the active configuration root, version, loaded-module information, Sofia/gateway state, package inventory and supplementary FreeSWITCH paths. The export can contain SIP credentials and other secrets, so it must be copied to secure storage and must never be committed to this repository.

After Debian and the required FreeSWITCH package/module set are installed, `07a-restore-freeswitch-config.sh` verifies the exported archive, backs up the fresh Debian configuration, stops FreeSWITCH and applies the exported configuration. It deliberately does **not** claim that the restored configuration is production-ready: `08-freeswitch-smoke-test.sh` and `docs/FREESWITCH_TEST_PLAN.md` are the acceptance gates.

## Important safety rule

Do not run `06-write-debian.sh` until the passive node has successfully completed the non-destructive rescue test for its exact hardware/source-OS profile and returned to CentOS. The write script requires an explicit `ERASE_CENTOS` confirmation and refuses to operate on a mounted target device.

In addition, **a successful script result is not production approval**. The process remains untested end to end until the documented tests have actually been completed, and a production migration requires peer technical review/approval of the exact release package.

## Current technical assumptions

- Supported source profiles are Raspberry Pi 3 / CentOS 7 and Raspberry Pi 4 / CentOS 9.
- Debian 13 (Trixie) arm64 is the target.
- The Pi 4 / CentOS 9 profile uses its own tested rescue build and hardware validation.
- Wired Ethernet is preferred for the migration path.
- VPN terminates independently on the site router.
- The site uses a two-node FreeSWITCH arrangement, with one node able to remain active while the passive node is rebuilt.
- Both nodes use 32 GB SD cards unless site preflight proves otherwise.

All assumptions must be confirmed by `01-preflight.sh` before migration.
