# kexec lab validation

## Purpose

This document records non-production validation of the kexec readiness workflow on `admin-01` before the same checks are run against the supported CentOS source profiles.

The production migration profiles remain:

| Profile | Source | Target |
| --- | --- | --- |
| `PI3-CENTOS7` | Raspberry Pi 3 / CentOS 7 | Debian 13 arm64 |
| `PI4-CENTOS9` | Raspberry Pi 4 / CentOS 9 | Debian 13 arm64 |

`admin-01` is **not** an approved source profile. It is being used only to exercise the kexec discovery/readiness process safely on a Raspberry Pi 3.

## Lab host

Observed on 2026-09-11:

```text
hostname=admin-01
model=Raspberry Pi 3 Model B Rev 1.2
arch=aarch64
kernel=6.18.39+rpt-rpi-v8
os=Debian GNU/Linux 13 (trixie)
os_id=debian
os_version=13
```

Network/storage evidence:

```text
management Ethernet: eth0 / 192.168.2.48/24
secondary WLAN:       wlan0 / 192.168.2.121/24
default route:        192.168.2.1 via eth0
root filesystem:      /dev/mmcblk0p2 / ext4
boot filesystem:      /dev/mmcblk0p1 mounted at /boot/firmware
SD card:              /dev/mmcblk0, approximately 59.4 GiB
```

## kexec userspace result

`kexec-tools` was installed successfully and the command is available:

```text
/usr/sbin/kexec
kexec-tools 2.0.29
```

The installed tool recognises ARM64 kernel formats including `Image`, `vmlinux`, `uImage` and `vmlinuz`, and supports ARM64 options such as `--dtb` and `--initrd`.

**Lab result:** userspace kexec tooling is present and usable.

## Matching boot artifacts

The readiness script identified boot artifacts matching the running kernel:

```text
/boot/vmlinuz-6.18.39+rpt-rpi-v8
/boot/initrd.img-6.18.39+rpt-rpi-v8
```

The live firmware device tree is also available:

```text
/sys/firmware/fdt
```

For this Raspberry Pi 3 model, the boot filesystem also contains:

```text
/boot/firmware/bcm2710-rpi-3-b.dtb
```

The live FDT is preferred for a same-kernel proof because it represents the device tree actually supplied to the running kernel.

## Readiness-script result

Command used:

```bash
sudo bash scripts/00-source-kexec-preflight.sh \
  2>&1 | tee ~/kexec-preflight-admin-01.txt
```

Observed summary:

```text
checks_pass=8
checks_warn=2
checks_fail=2
detected_kernel_image=/boot/vmlinuz-6.18.39+rpt-rpi-v8
detected_initrd_image=/boot/initrd.img-6.18.39+rpt-rpi-v8
KEXEC_OS_READY=NO
KEXEC_LOAD_UNLOAD_TEST_REQUIRED=YES
```

### Why the result is `NO`

Two failures were observed:

1. **Unsupported source OS** — this is expected. `admin-01` is Debian 13, while the production workflow intentionally accepts only CentOS 7 and CentOS 9 source systems.
2. **No positive `CONFIG_KEXEC=y` or `CONFIG_KEXEC_FILE=y` evidence** was found in `/boot/config-6.18.39+rpt-rpi-v8`.

The second result means the static configuration check does not prove kexec support. It should be treated as unresolved until a controlled load/unload test is performed. The absence of the usual `/proc/sys/kernel/kexec_load_disabled` and loaded-state interfaces also does not, by itself, prove that kexec is unavailable.

The readiness script is intentionally conservative and fails closed.

## Non-destructive same-kernel proof

Before any rescue-kernel execution, the next lab step is to attempt to load the **currently running kernel** plus its matching initramfs into the kexec slot and then immediately unload it.

This test must **not** execute the loaded kernel.

First preserve the live device tree:

```bash
sudo cp /sys/firmware/fdt /root/kexec-current.dtb
sudo ls -lh /root/kexec-current.dtb
```

Load the same running kernel configuration:

```bash
sudo kexec -l \
  /boot/vmlinuz-6.18.39+rpt-rpi-v8 \
  --initrd=/boot/initrd.img-6.18.39+rpt-rpi-v8 \
  --dtb=/root/kexec-current.dtb \
  --reuse-cmdline

echo "kexec_load_rc=$?"
```

A return code of `0` proves that the running kernel accepted a kexec target through the installed tool/syscall path.

**Do not run `kexec -e` during this proof.**

Immediately unload the pending kernel:

```bash
sudo kexec -u

echo "kexec_unload_rc=$?"
```

Expected result:

```text
kexec_load_rc=0
kexec_unload_rc=0
```

If the load fails, repeat with debug enabled and retain the output as evidence:

```bash
sudo kexec -d -l \
  /boot/vmlinuz-6.18.39+rpt-rpi-v8 \
  --initrd=/boot/initrd.img-6.18.39+rpt-rpi-v8 \
  --dtb=/root/kexec-current.dtb \
  --reuse-cmdline
```

## Production-profile implication

A successful Debian lab proof demonstrates the mechanics of loading/unloading a kernel on Raspberry Pi 3 hardware, but it does **not** approve either production profile.

The same static readiness and same-kernel load/unload proof must be completed independently on:

```text
PI3-CENTOS7  -> actual Raspberry Pi 3 / CentOS 7 target
PI4-CENTOS9  -> actual Raspberry Pi 4 / CentOS 9 target
```

Only after a profile passes its own load/unload proof should the project proceed to building and executing that profile's RAM-rescue kernel/initramfs/DTB combination.

## Safety status

The recorded `admin-01` checks were non-destructive:

```text
kexec_load_attempted=NO       # during the static preflight run
disk_write_attempted=NO
boot_files_modified=NO
kexec_execute_attempted=NO
```

The future same-kernel proof may perform `kexec -l` and `kexec -u`, but must not perform `kexec -e`.
