# Higher-Risk Fully Automated Script

## Purpose

This document describes a possible **one-command / highly automated** version of the Raspberry Pi rebuild workflow. It is intentionally classified as **higher risk** than the standard release-day process because it would chain together backup, rescue entry, destructive SD-card overwrite, first boot, FreeSWITCH restoration and validation with much less human inspection between stages.

The standard `docs/RELEASE_DAY.md` procedure remains the preferred production method. This document is a design option for later development and testing; it is **not approval to bypass the existing GO/NO-GO gates**.

## Supported migration profiles

Any automated implementation must require an explicit profile and must refuse ambiguous hardware/OS combinations.

| Profile | Source | Target |
| --- | --- | --- |
| `PI3-CENTOS7` | Raspberry Pi 3 / CentOS 7 | Debian 13 arm64 |
| `PI4-CENTOS9` | Raspberry Pi 4 / CentOS 9 | Debian 13 arm64 |

A Pi 4 / CentOS 9 run must use the separately proven Pi 4 rescue kernel/initramfs/DTB combination. A rescue profile validated on Pi 3 / CentOS 7 must not be silently reused.

## Why this is higher risk

A fully automated orchestrator can reduce typing and make repeat runs consistent, but it also compresses several deliberate decision points. The main risks are selecting the wrong node or SD-card device, automatically proceeding after a warning, entering rescue before backup/export verification, overwriting CentOS after VPN degradation, applying the wrong hardware/OS rescue profile, restoring incompatible FreeSWITCH configuration/modules, interpreting process-level success as service acceptance and automatically failing production service over before call-path validation.

For that reason, **full automation must never mean removal of validation**. It means automating the checks and enforcing the decision gates in code.

## Proposed command

A future controller could look approximately like:

```powershell
pwsh .\scripts\powershell\Invoke-FullyAutomatedRebuild.ps1 `
  -Profile PI4-CENTOS9 `
  -Target <user@passive-pi-ip> `
  -Peer <user@active-pi-ip> `
  -Router <router-ip> `
  -SiteConfig 'C:\pios-rebuild-secure\passive-site.env' `
  -ArtifactDirectory 'C:\pios-rebuild-artifacts\passive' `
  -ApprovedImage 'C:\pios-images\pios-debian13-arm64.img.xz' `
  -ApprovedImageSHA512 '<sha512>' `
  -ReleaseCommit '<full-git-sha>' `
  -ConfirmDestructiveRebuild 'ERASE_PASSIVE_NODE'
```

The final implementation should make destructive confirmation deliberately difficult to supply accidentally and should bind it to the expected node identity.

## Mandatory preconditions

The orchestrator must stop before doing anything destructive unless all of the following are true:

```text
[PASS] explicit migration profile selected
[PASS] exact Raspberry Pi model matches profile
[PASS] current CentOS ID/version matches profile
[PASS] node role independently confirmed as PASSIVE
[PASS] peer/active node reachable and healthy
[PASS] router-hosted VPN reachable
[PASS] exact Git release commit checked out and working tree clean
[PASS] approved Debian image checksum matches
[PASS] approved rescue build identity matches the profile
[PASS] rescue round-trip proof exists for this hardware/OS profile
[PASS] FreeSWITCH Debian compatibility test exists
[PASS] configuration/inventory export completed
[PASS] FreeSWITCH export completed and checksum verified off-node
[PASS] full 32 GB SD rollback image completed and checksum verified off-node
[PASS] target whole-disk identity matches the recorded device
[PASS] enough workstation storage remains
```

Any failed mandatory precondition means **STOP**. The automation must not offer a generic `-Force` option that bypasses these gates.

## Proposed automated sequence

### Stage A - Release environment

1. Confirm repository working tree is clean.
2. `git fetch origin --prune`.
3. `git checkout main`.
4. `git pull --ff-only origin main`.
5. Record full release commit.
6. Lock the run to that commit; no further Git update during execution.

### Stage B - Workstation and site preflight

1. Verify PowerShell/OpenSSH/Git requirements.
2. Verify at least the configured free-space threshold; 80 GB remains the recommended two-card working minimum.
3. Verify router/VPN reachability.
4. Verify SSH to both nodes.
5. Verify active peer remains healthy.

### Stage C - Source identity and inventory

1. Run Linux-side `01-preflight.sh`.
2. Verify selected profile against Pi model, architecture and CentOS version.
3. Capture package/service/network inventory.
4. Export FreeSWITCH configuration and runtime state.
5. Copy artifacts to the workstation.
6. Verify copied checksums.

### Stage D - Full rollback image

1. Reconfirm target whole SD-card device.
2. Read the complete 32 GB card over SSH to the workstation.
3. Verify expected byte count.
4. Produce SHA-256.
5. Confirm image and checksum sidecar exist off-node.

Failure here is an automatic NO-GO.

### Stage E - Rescue readiness

1. Run `03-rescue-readiness.sh`.
2. Match rescue kernel/initramfs/DTB metadata against the selected profile.
3. Verify active peer again.
4. Load rescue with `04-load-rescue.sh` without executing it.
5. Verify the kernel reports a loaded kexec image where supported.

### Stage F - Final automated destructive checkpoint

Immediately before entering rescue, the controller should print and log:

```text
PROFILE
TARGET HOSTNAME
TARGET IP
TARGET MAC
TARGET PI MODEL
CURRENT CENTOS VERSION
TARGET SD DEVICE
TARGET SD CAPACITY
PEER ACTIVE HOST
ROLLBACK IMAGE PATH + SHA256
DEBIAN IMAGE PATH + SHA512
RESCUE BUILD ID
RELEASE COMMIT
```

The run may only continue if every value matches the recorded run manifest and the explicit destructive confirmation was supplied.

### Stage G - Enter and validate RAM rescue

1. Execute the already-loaded rescue.
2. Wait for normal SSH to disappear.
3. Poll only for the expected rescue SSH endpoint for a bounded period.
4. Reconnect to rescue.
5. Verify root is RAM/initramfs.
6. Verify expected Pi model and network identity.
7. Verify the 32 GB target device is visible.
8. Verify the target and all child partitions are unmounted.
9. Verify the active peer remains healthy from the workstation.

If rescue validation fails, do **not** attempt the Debian write.

### Stage H - Debian image write

Use the existing Linux rescue-side `06-write-debian.sh` rather than implementing a second independent destructive writer in PowerShell. The Linux script remains responsible for RAM-root validation, whole-disk validation, target-unmounted validation, expected-device matching, approved image checksum validation where applicable and literal destructive confirmation.

The PowerShell controller should orchestrate and log the operation, not weaken those checks.

### Stage I - Offline Debian configuration

Before reboot, automatically verify/apply only the values proven in testing: hostname, SSH public key, expected network configuration and required first-boot settings. Inspect the Debian root/boot filesystems and only reboot if offline validation passes.

### Stage J - First boot validation

1. Reboot.
2. Wait for rescue SSH to disappear.
3. Wait for normal Debian SSH to return, with a bounded timeout.
4. Run `07-validate-debian.sh`.
5. Verify hostname, IP/MAC, route, DNS, time and systemd health.

A failed Debian validation must leave production on the peer node and stop the automated sequence.

### Stage K - FreeSWITCH restore and validation

1. Copy the verified export and checksum to Debian.
2. Verify the required package/module set is present.
3. Run `07a-restore-freeswitch-config.sh` with explicit restore confirmation.
4. Run `08-freeswitch-smoke-test.sh --start`.
5. Capture service status, Sofia/gateway state, registrations and logs.

The automated controller may perform deterministic smoke tests, but it must **not claim production acceptance solely from process/service status**.

## What should remain manual

Even in the higher-risk automated mode, keep these as separate human release decisions:

1. **Production failover.** Do not automatically move live service to the rebuilt node at the end of the OS rebuild.
2. **Critical call-path acceptance.** Inbound/outbound calls, two-way audio, DTMF, caller ID and site-specific call flows require explicit acceptance unless trustworthy synthetic call testing is later built.
3. **Second-node rebuild approval.** Do not automatically rebuild the second Pi immediately after the first succeeds. Complete the agreed passive/production soak first.

The automated boundary should therefore be:

```text
CentOS PASSIVE
   -> protected backup
   -> RAM rescue
   -> Debian
   -> configuration restore
   -> automated validation
   -> READY FOR SOAK
```

not an unattended rebuild of both nodes plus automatic failover and retirement of rollback.

## State file / resumability

A future implementation should keep a checksum-protected run manifest, for example:

```text
artifacts/<change-reference>/run-state.json
```

with states such as:

```text
RELEASE_PINNED
PREFLIGHT_PASSED
EXPORT_PASSED
ROLLBACK_IMAGE_VERIFIED
RESCUE_LOADED
RESCUE_VALIDATED
DESTRUCTIVE_WRITE_STARTED
DEBIAN_WRITTEN
DEBIAN_BOOTED
DEBIAN_VALIDATED
FREESWITCH_RESTORED
SMOKE_TEST_PASSED
READY_FOR_SOAK
ROLLED_BACK
FAILED
```

The controller must verify the observable result before advancing state.

## Timeouts and retry behaviour

Retries must be bounded. Use several short retries for ordinary SSH/reachability checks and bounded multi-minute waits for rescue or Debian boot transitions. Never use an infinite retry around image writes and never automatically repeat a failed destructive write without re-validating target identity and run state.

## Logging

Produce one timestamped release log containing Git commit, profile, node identities, stage start/finish times, stdout/stderr from remote stages, checksums/artifact paths, every GO/NO-GO result, the destructive checkpoint and final state. Do not write secrets from FreeSWITCH exports, SSH keys or repository credentials into ordinary logs.

## Rollback behaviour

Automation may assist rollback, but it should not silently choose rollback after a destructive failure. Stop in a known state and present the applicable action:

| State | Expected response |
| --- | --- |
| Before rescue | Stop; CentOS unchanged |
| Rescue running, SD untouched | Reboot to CentOS |
| Debian write started/finished, rescue healthy | Offer controlled restore of verified CentOS image |
| Debian booted but validation failed | Keep peer carrying service; repair/rebuild passive |
| FreeSWITCH validation failed | Keep peer carrying service; restore clean Debian config or rebuild |

A later `-Rollback` mode could automate a previously rehearsed image restore, but it should still require explicit node/disk confirmation.

## Development gates before production use

Do not use a future fully automated orchestrator against a production Pi until it has passed:

1. PowerShell unit/static checks.
2. Dry-run mode proving no mutation occurs.
3. Lab Pi 3 / CentOS 7 full migration test if that profile remains required.
4. Lab Pi 4 / CentOS 9 full migration test.
5. Deliberate wrong-model refusal test.
6. Deliberate wrong-OS-version refusal test.
7. Deliberate wrong-target-device refusal test.
8. Corrupt/missing rollback image refusal test.
9. Wrong Debian checksum refusal test.
10. Network-loss tests at major transitions.
11. Rescue-not-reachable test.
12. Debian-first-boot-failure test.
13. FreeSWITCH-restore-failure test.
14. Rehearsed rollback from RAM rescue.
15. Release-day review and approval of the exact automation commit.

## Recommendation

Build this only after the standard Pi 4 / CentOS 9 and Pi 3 / CentOS 7 assisted workflows have been proven. The useful target is **high automation with hard gates**, not genuinely unattended rebuilding of both production nodes.

The safer production boundary is:

> one command may rebuild and validate the **passive** node, but production failover and approval to rebuild the peer remain separate release decisions.
