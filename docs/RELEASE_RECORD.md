# Electronic Release Record

## Purpose

The release procedure is designed to be run electronically. You do **not** need to print `RELEASE_DAY.md` and fill it in by hand.

`docs/RELEASE_DAY.md` remains the master operating procedure. Before the maintenance window, create a **local dated release record** for the specific Pi being rebuilt and keep that Markdown file open while you work.

Populated release records are written under `releases/` by default. That directory is ignored by Git because the record can contain site-specific hostnames, IP addresses, MAC addresses, artifact paths and operational evidence.

## Create the record

Run this after the Git checkout has been updated and the exact release commit has been pinned.

### Raspberry Pi 4 / CentOS 9 example

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

### Raspberry Pi 3 / CentOS 7 example

```powershell
pwsh .\scripts\powershell\01-create-release-record.ps1 `
  -Profile PI3-CENTOS7 `
  -Target <user@passive-pi-ip> `
  -Active <user@active-pi-ip> `
  -Router <router-ip> `
  -Site '<site-name>' `
  -ChangeReference '<change-reference>' `
  -SdDevice /dev/mmcblk0 `
  -DebianImage 'C:\pios-images\pios-debian13-arm64.img.xz'
```

If `-ChangeReference` is omitted, the script creates a timestamp-based reference. If `-DebianImage` is supplied, the script calculates and records the local image SHA512.

## What the script fills in automatically

The script performs read-only checks and records:

- date/time;
- engineer name from Git configuration where available;
- exact Git branch and commit;
- selected migration profile;
- target and active SSH endpoints;
- target hostname;
- active hostname;
- Raspberry Pi model;
- architecture;
- current OS name, ID and version;
- management-interface MAC address;
- configured SD device and detected capacity;
- VPN router value supplied on the command line;
- Debian image path and SHA512 when supplied.

It then compares the detected target against the selected profile.

For example, `PI4-CENTOS9` expects:

```text
Raspberry Pi 4
CentOS 9
arm64/aarch64
```

A mismatch creates the evidence record but returns a **NO-GO** result. It does not change the Pi.

## Example successful output

```text
===== RESULT =====
release_record=C:\...\pios-rebuild\releases\2026-09-11-pi-b-pi4-centos9-release.md
profile_hardware=PASS
profile_os=PASS
profile_arch=PASS
profile_gate=PASS
RELEASE_RECORD_CREATED=YES
RELEASE_PROFILE_GATE=PASS
```

Open the generated Markdown file in VS Code, Notepad, Obsidian or another text editor and update the release-gate table as the work progresses.

## What remains manual in the record

Some items cannot safely be inferred in advance and should be entered as they occur:

- planned/actual start and finish times where different from creation time;
- rescue build/kernel/initramfs/DTB identity;
- rescue round-trip evidence reference;
- rollback image filename and SHA256;
- FreeSWITCH export filename and SHA256;
- GO/NO-GO decisions at each gate;
- functional call-test results;
- incident/defect references;
- rollback decision if required;
- final migration result and soak decision.

The PowerShell helpers can later be extended to append more of this evidence automatically.

## Handling the completed record

The generated file is local operational evidence and is not committed automatically.

At the end of the change:

1. make sure every release gate has a result;
2. add the final outcome and actual finish time;
3. retain the file with the migration artifacts;
4. attach or paste it into the approved change/ticket system if required;
5. do not commit it to Git unless site-specific data has been reviewed and repository storage is explicitly approved.

The project template itself remains at `docs/RELEASE_RECORD_TEMPLATE.md` and is safe to keep in Git.
