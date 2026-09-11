# Higher-Risk Fully Automated Script — One-Button Rebuild

## Goal

The fully automated option should be a **true one-button operator job** from the Windows administration laptop.

The operator should not have to run ten separate commands. They should prepare a site/profile configuration in advance, double-click or launch one entry point, review one final summary, press **START REBUILD**, and then let the controller carry the passive node through the complete automated rebuild sequence.

The target operator experience is:

```text
ONE BUTTON
    |
    v
preflight -> backup -> config export -> rescue -> Debian write
    -> first boot -> FreeSWITCH restore -> automated validation
    -> READY FOR SOAK
```

The job must stop automatically on any failed safety gate. It must **not** automatically fail production traffic over or immediately rebuild the second Pi.

## Supported profiles

| Profile | Source | Target |
| --- | --- | --- |
| `PI3-CENTOS7` | Raspberry Pi 3 / CentOS 7 | Debian 13 arm64 |
| `PI4-CENTOS9` | Raspberry Pi 4 / CentOS 9 | Debian 13 arm64 |

The selected profile controls the expected Pi model, CentOS version, rescue build and validation rules. A Pi 3 rescue build must never be silently reused for Pi 4 / CentOS 9.

## One-button entry point

The intended final entry point is:

```text
ONE-BUTTON-REBUILD.cmd
```

or, directly from PowerShell:

```powershell
pwsh .\scripts\powershell\Invoke-FullyAutomatedRebuild.ps1 `
  -ConfigFile 'C:\pios-rebuild-secure\site-rebuild.json'
```

The `.cmd` launcher should simply locate PowerShell 7, locate the repository, load the pre-created configuration and start the PowerShell orchestrator. All engineering logic belongs in the PowerShell orchestrator, not in the batch file.

## Single operator interaction

The one-button workflow should have **one deliberate destructive approval at the beginning**.

Before enabling the START button, the screen should display:

```text
CHANGE REFERENCE
MIGRATION PROFILE
TARGET HOSTNAME
TARGET IP
TARGET MAC
RPI MODEL
CURRENT CENTOS VERSION
TARGET SD DEVICE
SD CAPACITY
ACTIVE/PEER NODE
DEBIAN IMAGE
DEBIAN SHA512
RESCUE BUILD ID
ROLLBACK DIRECTORY
GIT RELEASE COMMIT
```

The operator then selects:

```text
[ START REBUILD ]
```

That one action authorises the orchestrator to perform the previously tested passive-node rebuild. There should be no repeated "Are you sure?" prompts after that. Safety comes from **hard technical gates**, not from making the operator repeatedly type confirmations.

The start screen must also make clear:

> This will erase and rebuild the selected PASSIVE Raspberry Pi if every automated safety gate passes.

Closing the window or selecting Cancel before START performs no remote change.

## Configuration-driven operation

All values required by the job should be prepared before release day in one protected configuration file outside the Git repository, for example:

```json
{
  "changeReference": "CHG-12345",
  "profile": "PI4-CENTOS9",
  "router": "<router-ip>",
  "target": "<user@passive-pi-ip>",
  "peer": "<user@active-pi-ip>",
  "targetHostname": "<passive-hostname>",
  "targetMac": "<mac>",
  "targetDisk": "/dev/mmcblk0",
  "targetCapacityGB": 32,
  "siteConfig": "C:\\pios-rebuild-secure\\passive-site.env",
  "artifactDirectory": "C:\\pios-rebuild-artifacts\\passive",
  "debianImage": "C:\\pios-images\\pios-debian13-arm64.img.xz",
  "debianImageSHA512": "<approved-sha512>",
  "rescueBuildId": "<approved-rescue-build-id>",
  "releaseCommit": "<full-git-sha>"
}
```

The configuration contains deployment metadata, not private SSH keys or SIP passwords. Secrets remain in approved protected locations.

## What the one-button job does

After START, the controller performs the following without further routine operator input.

### 1. Freeze the release environment

- verify the repository is at the recorded release commit;
- verify the working tree is clean;
- do **not** run another `git pull` after the job begins;
- create a timestamped release log and run-state file.

### 2. Validate the administration laptop

- PowerShell/OpenSSH/Git available;
- VPN/router reachable;
- both Pis reachable;
- at least the configured free-space requirement available;
- for the two 32 GB card workflow, 80 GB remains the recommended starting minimum;
- Debian image exists locally;
- local SHA512 exactly matches the approved value.

### 3. Prove target and peer identity

The target must match the selected profile and the peer must be healthy.

For `PI4-CENTOS9` this means, among other checks:

```text
Raspberry Pi 4
CentOS 9
target role = PASSIVE
peer reachable and carrying service
whole SD device = expected recorded device
```

Any profile/model/source-OS mismatch is an immediate STOP.

### 4. Capture final inventory

Automatically run the existing Linux-side stages for:

- preflight;
- package/service/network inventory;
- FreeSWITCH version/module/Sofia/gateway state;
- configuration export.

Copy all output to the administration laptop.

### 5. Verify FreeSWITCH export off-node

The job confirms the expected archive and checksum sidecar exist locally and records their hashes in the run manifest.

No valid export = no destructive stage.

### 6. Take the full 32 GB rollback image

Automatically read the complete confirmed SD device over SSH to the laptop, produce the SHA-256 sidecar, validate expected size and record the artifact in the manifest.

No valid full-card rollback image = no destructive stage.

### 7. Run rescue readiness

Automatically run the profile-specific rescue readiness check and confirm:

- model/architecture;
- kexec capability;
- wired network/default route;
- target device;
- rescue kernel/initramfs/DTB identity.

### 8. Load the already-tested rescue

Load the rescue image into the kexec slot without executing it, then verify the loaded state where supported.

### 9. Re-check the active peer

Immediately before leaving CentOS on the passive node, prove the peer is still reachable and healthy.

If the peer is unhealthy, stop while the passive node is still on its original CentOS installation.

### 10. Enter RAM rescue

Execute the tested rescue and automatically wait for normal SSH to disappear and the expected rescue SSH port to become available.

The wait must have a bounded timeout. It must never retry forever.

### 11. Validate rescue before touching the SD card

The controller verifies remotely that:

```text
root filesystem = RAM/initramfs
correct Pi model = PASS
expected network = PASS
correct SD device visible = PASS
target and all child partitions unmounted = PASS
peer still healthy = PASS
```

Any failure means the Debian write is not started.

### 12. Stream and write the approved Debian image

The Windows controller streams the already checksum-verified image to the rescue environment. The rescue-side writer remains authoritative for:

- RAM-root verification;
- expected Pi model;
- exact whole-disk target;
- unmounted target and child partitions;
- destructive state;
- write/sync result.

The one-button controller must **not** contain a generic `-Force` path around these checks.

### 13. Configure Debian before first boot

Using the already-tested first-boot method, automatically apply only the approved node-specific values such as:

- hostname;
- administration SSH public key;
- network configuration/DHCP expectations;
- any required first-boot marker/settings.

Then inspect the new root/boot filesystems before reboot.

### 14. Reboot and wait for Debian

The controller reboots the Pi, waits for rescue SSH to disappear and waits for normal Debian SSH to return within a bounded timeout.

### 15. Validate Debian

Automatically run `07-validate-debian.sh` and verify:

- Debian 13;
- expected Raspberry Pi model;
- expected architecture;
- SSH;
- network/default route;
- expected IP/MAC where configured;
- DNS;
- systemd health;
- storage state.

Failure stops the job with production still on the untouched peer.

### 16. Restore FreeSWITCH

Copy the verified FreeSWITCH export and sidecar back to the rebuilt Debian node, verify required packages/modules, back up the clean Debian FreeSWITCH configuration and apply the migrated configuration.

### 17. Run automated FreeSWITCH checks

Automatically run the smoke test and collect:

- service status;
- FreeSWITCH version;
- loaded modules;
- Sofia profile status;
- gateway state;
- registrations;
- listening sockets;
- recent service logs.

### 18. Finish at READY FOR SOAK

If every automated gate passes, the one-button job ends with:

```text
==========================================
ONE-BUTTON REBUILD: SUCCESS
==========================================
Target:            <hostname>
Profile:           PI4-CENTOS9
OS:                Debian 13
Debian validation: PASS
FreeSWITCH smoke:  PASS
Rollback image:    VERIFIED
Peer:              HEALTHY
Final state:       READY FOR SOAK
==========================================
```

The operator receives the location of the release log, run manifest, backup and test evidence.

## What the button deliberately does NOT do

A successful one-button rebuild must **not** automatically:

- move production service to the new Debian node;
- declare live telephony acceptance without real call-path tests;
- rebuild the second Pi;
- delete the CentOS rollback image;
- remove the original peer from service.

Those remain later release decisions after the 24-48 hour passive soak and controlled production failover.

This keeps the one-button boundary at:

```text
PASSIVE CENTOS NODE
        |
        | one button
        v
PASSIVE DEBIAN NODE
VALIDATED + READY FOR SOAK
```

## Automatic stop conditions

The job immediately stops if any mandatory gate fails, including:

```text
wrong migration profile
wrong Pi model
wrong CentOS version
wrong/uncertain target disk
active peer unhealthy
VPN/router unstable
Git commit mismatch
Debian checksum mismatch
FreeSWITCH export missing/corrupt
rollback image missing/corrupt
rescue profile mismatch
rescue unreachable
rescue root not RAM-resident
target mounted
Debian first boot timeout
Debian validation failure
FreeSWITCH restore/smoke-test failure
```

There is no `IgnoreErrors`, `ContinueAnyway` or general-purpose `Force` mode for production use.

## State and resumability

The job should maintain:

```text
artifacts/<change-reference>/run-state.json
```

with verified states such as:

```text
STARTED
RELEASE_PINNED
LAPTOP_PREFLIGHT_PASSED
TARGET_IDENTIFIED
EXPORT_VERIFIED
ROLLBACK_IMAGE_VERIFIED
RESCUE_READY
RESCUE_LOADED
RESCUE_VALIDATED
DESTRUCTIVE_WRITE_STARTED
DEBIAN_WRITTEN
DEBIAN_BOOTED
DEBIAN_VALIDATED
FREESWITCH_RESTORED
SMOKE_TEST_PASSED
READY_FOR_SOAK
FAILED
ROLLED_BACK
```

A stage is only recorded after its observable result has been verified.

If the job is interrupted, a later resume function must read this state and revalidate reality before continuing. It must not simply continue from the last line in a file.

## Rollback

The one-button rebuild should not silently perform a destructive rollback. If a problem occurs after the Debian write has started, the controller stops, records the exact state and presents the relevant rollback action.

A separate **ROLL BACK PASSIVE NODE** button can be designed later, using the already verified full-card image and the same strict target identity checks.

## Test requirement before enabling the button in production

The one-button option is not considered production-ready until it has passed, at minimum:

1. dry-run test with zero mutation;
2. wrong-profile rejection;
3. wrong-Pi-model rejection;
4. wrong-CentOS-version rejection;
5. wrong-target-device rejection;
6. wrong Debian checksum rejection;
7. missing/corrupt FreeSWITCH export rejection;
8. missing/corrupt rollback image rejection;
9. VPN/network loss during each transition;
10. rescue-not-reachable test;
11. complete lab Pi 4 / CentOS 9 -> Debian migration;
12. Pi 3 / CentOS 7 test if that profile remains required;
13. Debian first-boot failure test;
14. FreeSWITCH restore failure test;
15. rehearsed CentOS image rollback from RAM rescue;
16. repeated successful full runs from the same release commit.

## Final design rule

The fully automated option should therefore be **one operator button, many automated hard gates**.

The operator experience is simple; the engineering underneath remains deliberately cautious:

> **Press START once. If every gate is green, rebuild the passive Pi and finish at READY FOR SOAK. If any gate is not green, stop automatically before making the next risky change.**
