# START HERE - Raspberry Pi Remote Rebuild

This is the **operator start page**. It is written so that an engineer who has not worked on this project before can follow the normal release process in the correct order.

The detailed engineering documents still exist, but on the day of the change the normal path is:

```text
START-HERE.md
   -> create electronic release record
   -> RELEASE_DAY.md gates
   -> RUNBOOK.md only when more technical detail is needed
```

The project currently supports:

| Profile | Current machine | Target |
| --- | --- | --- |
| `PI3-CENTOS7` | Raspberry Pi 3 running CentOS 7 | Debian 13 arm64 |
| `PI4-CENTOS9` | Raspberry Pi 4 running CentOS 9 | Debian 13 arm64 |

For the Pi 4 estate running CentOS 9, use **`PI4-CENTOS9`**.

---

# The most important rule

At every step below there is an **expected PASS result**.

If the command fails, gives a different result, or you are uncertain what you are looking at:

> **STOP. Do not move to the next step.**

Do not change a device name, disable a safety check, use `-Force`, or substitute another rescue/image simply to make a failed gate pass.

The original active node must remain available while the passive node is rebuilt.

---

# Before you start

You need:

- a Windows administration laptop;
- PowerShell 7 (`pwsh`);
- Git for Windows;
- Windows OpenSSH client (`ssh.exe` and `scp.exe`);
- the site VPN connected;
- SSH access to both Raspberry Pis;
- mains power connected to the laptop;
- sleep/hibernate disabled for the change window;
- at least **80 GB free** if keeping raw rollback images of both 32 GB SD cards;
- the approved Debian image available locally;
- the already-tested RAM-rescue build for the exact profile being changed.

For a first-time Pi 4 / CentOS 9 migration, the Pi 4 rescue round trip must already have been proven before the production rebuild is attempted.

---

# Step 1 - Get the release code onto the laptop

Open **PowerShell 7**.

If this is the first time the laptop has used the repository:

```powershell
$RepoPath = Join-Path $HOME 'pios-rebuild'
git clone https://github.com/jrwroberts1976/pios-rebuild.git $RepoPath
Set-Location $RepoPath
```

If the repository already exists:

```powershell
$RepoPath = Join-Path $HOME 'pios-rebuild'
Set-Location $RepoPath

git status --short
git fetch origin --prune
git checkout main
git pull --ff-only origin main
```

`git status --short` should show **no uncommitted files** before the pull.

Now record the exact version being used:

```powershell
git status
git log -1 --oneline
$ReleaseCommit = (git rev-parse HEAD).Trim()
Write-Host "Release commit: $ReleaseCommit"
```

Or run the supplied helper:

```powershell
pwsh .\scripts\powershell\00-setup-environment.ps1 `
  -RepoPath $RepoPath `
  -Branch main
```

Expected result:

```text
ENVIRONMENT_SETUP=PASS
```

**From this point onward, do not run `git pull` again during the change.**

---

# Step 2 - Decide which migration profile applies

Do not guess. The existing hardware and operating system determine the profile.

```text
Pi 3 + CentOS 7 = PI3-CENTOS7
Pi 4 + CentOS 9 = PI4-CENTOS9
```

For a Pi 4 currently running CentOS 9:

```powershell
$Profile = 'PI4-CENTOS9'
```

This does **not** yet change the Pi. The later pre-flight checks independently prove that the machine really is a Pi 4 running CentOS 9.

If the detected machine does not match the selected profile, the release is a **NO-GO**.

---

# Step 3 - Create the live electronic release record

Do not print the runbook and write on it by hand.

Create one dated Markdown record for the Pi being changed. This is the live evidence file that stays open while the work is performed.

Pi 4 / CentOS 9 example:

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

Replace every value inside `<...>` with the real site value.

Example only:

```powershell
pwsh .\scripts\powershell\01-create-release-record.ps1 `
  -Profile PI4-CENTOS9 `
  -Target admin@10.10.20.22 `
  -Active admin@10.10.20.21 `
  -Router 10.10.20.1 `
  -Site 'Customer-Site-A' `
  -ChangeReference 'CHG-12345' `
  -SdDevice /dev/mmcblk0 `
  -DebianImage 'C:\pios-images\pios-debian13-arm64.img.xz'
```

The example IP addresses are illustrative only. Use the actual site values.

Expected result:

```text
RELEASE_RECORD_CREATED=YES
RELEASE_PROFILE_GATE=PASS
```

The command also prints the path of the generated record, for example:

```text
releases\2026-09-11-pi-b-pi4-centos9-release.md
```

Open that file in VS Code, Notepad, Obsidian or another text editor. Keep it open for the rest of the change.

If the result is `RELEASE_PROFILE_GATE=FAIL`, **stop**. Nothing destructive has happened.

---

# Step 4 - Create the protected site configuration

For Pi 4 / CentOS 9, copy:

```text
config/site-pi4-centos9.env.example
```

to a protected location outside the Git repository, for example:

```text
C:\pios-rebuild-secure\passive-site.env
```

For Pi 3 / CentOS 7, use:

```text
config/site.env.example
```

Populate the real node values.

For Pi 4 / CentOS 9, the important identity checks must remain equivalent to:

```text
EXPECTED_MODEL_REGEX='^Raspberry Pi 4'
EXPECTED_SOURCE_OS_ID='centos'
EXPECTED_SOURCE_OS_VERSION='9'
```

Do not weaken these values to make a mismatched machine pass.

In PowerShell set:

```powershell
$Config = 'C:\pios-rebuild-secure\passive-site.env'
```

---

# Step 5 - Prove the laptop, VPN and both Pis are reachable

Run:

```powershell
pwsh .\scripts\powershell\00-admin-laptop-preflight.ps1 `
  -Router <router-ip> `
  -Active <user@active-pi-ip> `
  -Passive <user@passive-pi-ip> `
  -MinFreeGB 80
```

Expected result:

```text
ADMIN_LAPTOP_PREFLIGHT=PASS
```

Before continuing, also confirm:

```text
[ ] VPN is connected
[ ] active Pi is reachable over SSH
[ ] passive Pi is reachable over SSH
[ ] active Pi is currently carrying service
[ ] passive Pi is the node intended for rebuild
[ ] no unrelated site/network incident is in progress
```

If any of those statements is uncertain, stop.

---

# Step 6 - Prove the passive Pi is the machine we think it is

Run the remote pre-flight:

```powershell
pwsh .\scripts\powershell\Invoke-PiosRemoteStage.ps1 `
  -Target <user@passive-pi-ip> `
  -RemoteScript 01-preflight.sh `
  -SiteConfig $Config
```

For `PI4-CENTOS9`, the evidence must show:

```text
Hardware      = Raspberry Pi 4
Architecture  = aarch64/arm64
Source OS     = CentOS 9
Target disk   = the expected whole SD-card device
Network       = expected management interface and default route
```

Expected overall result:

```text
PRECHECK_COMPLETE=YES
```

The detected values must also agree with the migration profile.

If it detects Pi 3, CentOS 7, the wrong architecture, an unexpected disk, or an unexpected boot/storage layout, stop.

---

# Step 7 - Capture the configuration and FreeSWITCH evidence

First collect the general inventory:

```powershell
pwsh .\scripts\powershell\Invoke-PiosRemoteStage.ps1 `
  -Target <user@passive-pi-ip> `
  -RemoteScript 02-backup-inventory.sh `
  -SiteConfig $Config
```

Then export FreeSWITCH configuration and runtime information:

```powershell
pwsh .\scripts\powershell\Invoke-PiosRemoteStage.ps1 `
  -Target <user@passive-pi-ip> `
  -RemoteScript 02a-export-freeswitch-config.sh `
  -SiteConfig $Config
```

Now copy the evidence off the Pi and onto the laptop:

```powershell
pwsh .\scripts\powershell\Copy-PiosArtifacts.ps1 `
  -Target <user@passive-pi-ip> `
  -OutputDirectory 'C:\pios-rebuild-artifacts\passive'
```

Expected result:

```text
ARTIFACT_COPY=PASS
```

Before continuing, prove that the copied directory contains the FreeSWITCH export and checksums.

Record the export filename and checksum in the live release record.

**Do not overwrite the SD card if the FreeSWITCH export is not safely off the Pi.**

---

# Step 8 - Take the complete rollback image

Use the whole SD-card device confirmed by Step 6.

Do not assume `/dev/mmcblk0` merely because that is common.

Run:

```powershell
pwsh .\scripts\powershell\02-full-sd-backup.ps1 `
  -Target <user@passive-pi-ip> `
  -Device <confirmed-whole-card-device> `
  -OutputDirectory 'C:\pios-rebuild-artifacts\passive' `
  -Label passive-centos-before-debian
```

Expected result:

```text
FULL_SD_BACKUP=PASS
```

The script should produce:

```text
<name>.img
<name>.img.sha256
```

Record both the rollback filename and SHA-256 in the live release record.

Do not continue if the image is unexpectedly small, missing, incomplete or cannot be checksummed.

Up to this point the process is still non-destructive to the installed OS.

---

# Step 9 - Prove the RAM rescue is ready

Run:

```powershell
pwsh .\scripts\powershell\Invoke-PiosRemoteStage.ps1 `
  -Target <user@passive-pi-ip> `
  -RemoteScript 03-rescue-readiness.sh `
  -SiteConfig $Config
```

Expected result:

```text
RESCUE_READY=YES
```

For a Pi 4 / CentOS 9 migration, the configured rescue kernel/initramfs/DTB/cmdline must be the **Pi 4 / CentOS 9 rescue build that was already tested non-destructively**.

Do not reuse a Pi 3 rescue merely because it worked on a Pi 3.

Now load the rescue without executing it:

```powershell
pwsh .\scripts\powershell\Invoke-PiosRemoteStage.ps1 `
  -Target <user@passive-pi-ip> `
  -RemoteScript 04-load-rescue.sh `
  -SiteConfig $Config
```

Loading rescue does not overwrite the SD card.

---

# Step 10 - Enter RAM rescue and prove it is safe

Before entering rescue, confirm again:

```text
[ ] active production node is healthy
[ ] VPN is stable
[ ] rollback image is on the laptop and checksummed
[ ] FreeSWITCH export is on the laptop and checksummed
[ ] correct passive Pi is selected
[ ] this exact profile's rescue round trip was previously tested
```

Then run:

```powershell
pwsh .\scripts\powershell\Invoke-PiosRemoteStage.ps1 `
  -Target <user@passive-pi-ip> `
  -RemoteScript 05-enter-rescue.sh `
  -SiteConfig $Config `
  -RemoteArgs ENTER_RESCUE
```

The normal SSH session is expected to disconnect.

Reconnect to the rescue environment:

```powershell
pwsh .\scripts\powershell\05-connect-rescue.ps1 `
  -Target <passive-pi-ip> `
  -Port 2222 `
  -User root
```

Inside the rescue shell run:

```bash
findmnt /
ip -br addr
ip route
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL
fdisk -l <confirmed-whole-card-device>
```

You must be able to prove all of these:

```text
[PASS] root filesystem is RAM/initramfs, not the SD card
[PASS] network interface is working
[PASS] default route is present
[PASS] rescue SSH is reachable across the VPN
[PASS] expected SD card is visible
[PASS] target SD card and all child partitions are unmounted
```

If any item fails, **do not write Debian**.

---

# Step 11 - Destructive point: write Debian to the passive Pi

This is the first point at which the existing CentOS installation is intentionally overwritten.

Before running the write, read and verify these values against the live release record:

```text
PROFILE
PASSIVE NODE HOSTNAME
PASSIVE NODE IP
PI MODEL
CURRENT CENTOS VERSION
WHOLE TARGET DISK
ROLLBACK IMAGE + SHA256
DEBIAN IMAGE + SHA512
ACTIVE PEER STATUS
```

Only continue when they all agree.

From the Linux RAM-rescue shell, run the already-tested writer:

```bash
bash /path/to/06-write-debian.sh \
  --target <confirmed-whole-card-device> \
  --image /path/to/approved-debian.img.xz \
  --confirm ERASE_CENTOS
```

Expected result:

```text
DEBIAN_IMAGE_WRITE_COMPLETE=YES
```

Do not bypass a mount, RAM-root, model, disk or checksum failure.

After the write, follow the tested procedure to apply the node's hostname, networking and SSH key while rescue is still available. Inspect the new Debian filesystems before rebooting.

---

# Step 12 - Boot Debian and validate it

When the offline checks are complete:

```bash
sync
reboot
```

Wait for normal SSH on the rebuilt Pi to return through the router VPN.

From PowerShell run:

```powershell
pwsh .\scripts\powershell\Invoke-PiosRemoteStage.ps1 `
  -Target <user@passive-pi-ip> `
  -RemoteScript 07-validate-debian.sh `
  -SiteConfig $Config
```

Expected result:

```text
DEBIAN_VALIDATION=PASS
```

Also verify:

```text
[ ] correct hostname
[ ] expected IP/MAC/interface
[ ] correct default gateway
[ ] DNS works
[ ] SSH key login works
[ ] time/date correct
[ ] no unexpected failed systemd units
[ ] storage layout correct
```

If Debian is reachable but validation fails, leave production on the untouched active CentOS node and stop the release at this point.

---

# Step 13 - Restore FreeSWITCH and test it

Make sure the Debian FreeSWITCH packages/modules required by the site are installed first.

Copy the previously verified FreeSWITCH export and its checksum sidecar to the rebuilt Pi.

Then run:

```powershell
pwsh .\scripts\powershell\Invoke-PiosRemoteStage.ps1 `
  -Target <user@passive-pi-ip> `
  -RemoteScript 07a-restore-freeswitch-config.sh `
  -SiteConfig $Config `
  -RemoteArgs @('--archive','/protected/path/freeswitch-config.tgz','--confirm','APPLY_FREESWITCH_CONFIG')
```

Then run the smoke test:

```powershell
pwsh .\scripts\powershell\Invoke-PiosRemoteStage.ps1 `
  -Target <user@passive-pi-ip> `
  -RemoteScript 08-freeswitch-smoke-test.sh `
  -SiteConfig $Config `
  -RemoteArgs '--start'
```

Expected result:

```text
FREESWITCH_SMOKE_TEST=PASS
```

Then complete the functional checks from `docs/FREESWITCH_TEST_PLAN.md`, including the applicable inbound/outbound call, RTP/audio, DTMF, gateway and registration tests.

A running FreeSWITCH process by itself is **not** production acceptance.

---

# Step 14 - Finish the first-node release

The expected successful end state is:

```text
ACTIVE NODE  = original CentOS node, still serving production
PASSIVE NODE = Debian 13, rebuilt and validated
NEXT ACTION  = 24-48 hour passive soak
```

Update the live release record with:

```text
actual finish time
Debian validation result
FreeSWITCH smoke-test result
functional-test result
issues/defects
final GO/NO-GO outcome
soak start time
```

Do **not** rebuild the active node simply because the first rebuild finished early.

The production failover is a separate controlled release after the passive soak.

---

# What happens if something fails?

Use this simple rule:

| Where it fails | What to do |
| --- | --- |
| Before RAM rescue | Stop. CentOS is unchanged. |
| RAM rescue running, SD card untouched | Reboot to CentOS. |
| Debian write has started/finished but rescue is still healthy | Use the tested rollback procedure to restore the verified CentOS image to the same confirmed SD card. |
| Debian boots but validation fails | Keep the other CentOS node active; repair/rebuild the passive node. |
| FreeSWITCH restore/testing fails | Keep the other CentOS node active; repair FreeSWITCH or rebuild the passive node. |
| Later production failover fails | Fail service back to the untouched CentOS node. |

Do not improvise a different recovery method during the release.

---

# Documents to use when more detail is needed

| Need | Document |
| --- | --- |
| The exact on-the-day gates | `docs/RELEASE_DAY.md` |
| How the electronic release record works | `docs/RELEASE_RECORD.md` |
| Pi 4 / CentOS 9 specifics | `docs/PI4_CENTOS9.md` |
| Full engineering procedure | `docs/RUNBOOK.md` |
| Windows/PowerShell details | `docs/POWERSHELL.md` |
| End-to-end testing | `docs/TEST_PLAN.md` |
| FreeSWITCH testing | `docs/FREESWITCH_TEST_PLAN.md` |
| Higher-risk future one-button design | `higher-risk-fully-automated-script.md` |

The higher-risk one-button document is not a replacement for this standard production process until that automation has been built, lab-tested and approved.