# Source Raspberry Pi prerequisites

This document covers prerequisites on the **existing CentOS Raspberry Pi before any RAM-rescue or Debian rebuild work begins**.

## Supported source profiles

| Migration profile | Source platform | Target |
| --- | --- | --- |
| `PI3-CENTOS7` | Raspberry Pi 3 / CentOS 7 | Debian 13 arm64 |
| `PI4-CENTOS9` | Raspberry Pi 4 / CentOS 9 | Debian 13 arm64 |

The migration concept is shared, but the kernel, initramfs, DTB, network drivers and rescue build must be proven separately for each profile.

## Mandatory package: kexec-tools

`kexec-tools` must be installed on the CentOS source Pi before the RAM-rescue stage. It provides the `kexec` command used to load the rescue kernel/initramfs into RAM and transfer execution to it.

### CentOS 7

```bash
sudo yum install -y kexec-tools
```

### CentOS 9

```bash
sudo dnf install -y kexec-tools
```

Verify on either profile:

```bash
command -v kexec
kexec --version
rpm -q kexec-tools
```

Expected result includes a valid `kexec` path, normally `/usr/sbin/kexec`, a version string and an installed `kexec-tools` RPM. Running `kexec -l` without a kernel is also a harmless command-presence check; it should print `No kernel specified` and usage information.

If the CentOS repositories cannot supply `kexec-tools`, stop and repair/approve the repository configuration before continuing. Do not bypass the RAM-rescue gate.

---

# Target-Pi kexec OS readiness check

Before building or loading any rescue image, run the standalone read-only check on **each target Pi**.

From the repository on the target Pi:

```bash
cd ~/pios-rebuild
sudo bash scripts/00-source-kexec-preflight.sh
```

Or, if the repository is staged elsewhere, run the script from that path.

The script performs no kernel load, no reboot and no disk write. It explicitly reports:

```text
kexec_load_attempted=NO
kexec_execute_attempted=NO
disk_write_attempted=NO
boot_files_modified=NO
```

The final status is one of:

```text
KEXEC_OS_READY=YES
KEXEC_OS_READY=PROVISIONAL
KEXEC_OS_READY=NO
```

Interpretation:

- `YES` - the static OS/kernel/tooling prerequisites are present. A controlled same-kernel load/unload proof is still mandatory before `kexec -e`.
- `PROVISIONAL` - no hard failure was found, but one or more items such as exported kernel config, exact boot artifact selection or lockdown state need review. A controlled load/unload proof is required.
- `NO` - a hard prerequisite failed. Do not proceed to the rescue stage.

The script is intentionally conservative. It will not turn a missing or ambiguous kernel/initramfs/DTB into a guessed load command.

## Manual copy/paste readiness commands

If the script is not yet present on a target, the following block gathers the same core evidence without changing the system:

```bash
echo "===== IDENTITY ====="
hostname -f 2>/dev/null || hostname
tr -d '\0' </proc/device-tree/model 2>/dev/null || true
echo
uname -a
uname -m
cat /etc/os-release
cat /etc/centos-release 2>/dev/null || true

echo
echo "===== KEXEC TOOL ====="
command -v kexec || true
kexec --version 2>/dev/null || true
rpm -q kexec-tools 2>/dev/null || true

echo
echo "===== KEXEC KERNEL SUPPORT ====="
if [ -r "/boot/config-$(uname -r)" ]; then
    grep -E '^CONFIG_KEXEC(=|_)' "/boot/config-$(uname -r)" || true
fi
if [ -r /proc/config.gz ]; then
    zgrep -E '^CONFIG_KEXEC(=|_)' /proc/config.gz || true
fi
if [ -r "/lib/modules/$(uname -r)/build/.config" ]; then
    grep -E '^CONFIG_KEXEC(=|_)' "/lib/modules/$(uname -r)/build/.config" || true
fi

echo
echo "===== KEXEC DISABLE / LOCKDOWN ====="
cat /proc/sys/kernel/kexec_load_disabled 2>/dev/null || echo "kexec_load_disabled not exposed"
cat /sys/kernel/security/lockdown 2>/dev/null || echo "kernel lockdown not exposed"

echo
echo "===== CURRENT COMMAND LINE ====="
cat /proc/cmdline

echo
echo "===== LIVE DEVICE TREE ====="
ls -lh /sys/firmware/fdt 2>/dev/null || echo "No /sys/firmware/fdt"

echo
echo "===== MATCHING BOOT FILES ====="
KREL="$(uname -r)"
for f in \
  "/boot/vmlinuz-$KREL" \
  "/boot/Image-$KREL" \
  "/boot/kernel-$KREL.img" \
  "/boot/initramfs-$KREL.img" \
  "/boot/initrd.img-$KREL" \
  "/boot/initrd-$KREL.img"; do
    [ -e "$f" ] && ls -lh "$f"
done

echo
echo "===== ALL POSSIBLE KERNEL / INITRAMFS / DTB FILES ====="
find /boot -maxdepth 4 -type f \
  \( -name 'vmlinuz*' \
     -o -name 'Image*' \
     -o -name 'kernel*.img' \
     -o -name 'initramfs*' \
     -o -name 'initrd*' \
     -o -name '*.dtb' \) \
  -print 2>/dev/null | sort

echo
echo "===== NETWORK ====="
ip -br link
ip -br addr
ip route

echo
echo "===== STORAGE ====="
findmnt /
findmnt /boot 2>/dev/null || true
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT,MODEL,SERIAL

echo
echo "===== SSH ====="
command -v sshd || ls -l /usr/sbin/sshd 2>/dev/null || true
systemctl is-active sshd 2>/dev/null || true
```

Save the output as release evidence for each target Pi.

## Kernel support is mandatory

Installing `kexec-tools` is not enough. The currently running CentOS kernel must support kexec.

Where the running kernel configuration is exposed, we want usable support such as:

```text
CONFIG_KEXEC=y
```

or a usable `CONFIG_KEXEC_FILE=y` configuration supported by the installed tool/kernel combination.

If no kernel configuration is exposed, that is **not automatically a failure**. Some kernels do not publish `/boot/config-*` or `/proc/config.gz`. In that case the result remains provisional until the controlled load/unload proof succeeds.

If the kernel configuration is present and explicitly lacks usable kexec support, the RAM-rescue method is **NO-GO** for that kernel. Installing the userspace package cannot add missing kernel functionality.

## ARM64 capability check

On an ARM64 source system, `kexec -l` help should list supported kernel types such as `Image`, `vmlinux`, `uImage` or `vmlinuz`, and ARM64 options including `--append`, `--dtb` and `--initrd`/`--ramdisk` where supported.

Record this output as release evidence because it confirms what kernel formats the installed kexec implementation can load.

## Controlled same-kernel load/unload proof

The static readiness check does **not** prove that the running kernel will accept a kexec load. Before any rescue execution, a separate controlled test must load the **same currently running kernel**, verify the load succeeds, then immediately unload it without executing it.

Do not construct this command by guessing paths. First review the output of `00-source-kexec-preflight.sh` and confirm:

- the kernel file exactly matches `uname -r` or is otherwise proven to be the currently running boot kernel;
- the initramfs is the matching current initramfs;
- the live FDT or correct profile-specific DTB is available;
- no production change is in progress;
- the node being tested is the intended passive/test node;
- `kexec -e` will **not** be run during this proof.

Typical ARM64 pattern after those values have been verified:

```bash
KERNEL=/boot/vmlinuz-$(uname -r)
INITRD=/boot/initramfs-$(uname -r).img
FDT=/root/kexec-current.dtb

cp /sys/firmware/fdt "$FDT"

kexec -l "$KERNEL" \
  --initrd="$INITRD" \
  --dtb="$FDT" \
  --reuse-cmdline

LOAD_RC=$?
echo "kexec_load_rc=$LOAD_RC"

# DO NOT run kexec -e during the readiness proof.

if [ "$LOAD_RC" -eq 0 ]; then
    kexec -u
    echo "kexec_unload_rc=$?"
fi
```

The CentOS 7 initramfs naming is commonly `/boot/initramfs-$(uname -r).img`, but **the actual target output is authoritative**. CentOS 9 or a Raspberry Pi-specific image layout may differ. Never substitute a guessed filename simply to make the command run.

A successful load followed by successful unload is the definitive pre-rescue proof that the currently running OS/kernel accepts kexec loading. It still does not prove that the custom rescue kernel/initramfs/network stack will work; that is established by the later non-destructive RAM-rescue round trip.

## Other source-node prerequisites

Before migration, each CentOS Pi must also have:

- stable wired Ethernet for the migration path;
- working SSH from the administration laptop through the router-hosted VPN;
- root/sudo access;
- known hostname, IP, MAC and default route;
- confirmed whole SD-card device identity;
- readable boot kernel/initramfs/DTB files for the selected rescue build;
- enough free filesystem space for temporary migration artifacts;
- completed FreeSWITCH configuration/runtime export copied off-node;
- verified full SD-card rollback image copied off-node before destructive work.

## Required preflight result

Run:

```bash
sudo bash scripts/00-source-kexec-preflight.sh
sudo ./scripts/01-preflight.sh
sudo ./scripts/03-rescue-readiness.sh
```

Before rescue execution, the important results must include an acceptable source-kexec result plus:

```text
kexec_tool=PASS
kexec_kernel=PASS
RESCUE_READY=YES
```

If the source readiness result is `PROVISIONAL`, the separately reviewed same-kernel load/unload proof must have passed and its evidence must be recorded before the rescue stage can be approved.

Do not run `kexec -e` unless the profile-specific rescue kernel, initramfs, DTB and network configuration have already been built, reviewed and non-destructively proven for that Pi/OS profile.

## kexec lifecycle

```text
kexec -l <kernel> ...  = load a kernel into RAM
kexec -u               = unload/cancel the pending kernel
kexec -e               = transfer execution to the loaded kernel
```

`kexec -e` is the point at which the current CentOS userspace and SSH session disappear.
