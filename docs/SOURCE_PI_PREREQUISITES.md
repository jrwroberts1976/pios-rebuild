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
```

Expected result includes a valid `kexec` path, normally `/usr/sbin/kexec`, and a version string. Running `kexec -l` without a kernel is also a harmless command-presence check; it should print `No kernel specified` and usage information.

If the CentOS repositories cannot supply `kexec-tools`, stop and repair/approve the repository configuration before continuing. Do not bypass the RAM-rescue gate.

## Kernel support is also mandatory

Installing `kexec-tools` is not enough. The currently running CentOS kernel must support kexec.

```bash
if [ -r "/boot/config-$(uname -r)" ]; then
    grep -E '^CONFIG_KEXEC(=|_)' "/boot/config-$(uname -r)"
fi

if [ -r /proc/config.gz ]; then
    zgrep -E '^CONFIG_KEXEC(=|_)' /proc/config.gz
fi
```

The rescue method requires usable kexec support, normally including:

```text
CONFIG_KEXEC=y
```

or a usable `CONFIG_KEXEC_FILE` configuration supported by the installed tool/kernel combination.

If no usable kexec capability is present in the running kernel, the RAM-rescue method is **NO-GO** for that kernel. Installing the userspace package cannot add missing kernel functionality.

## ARM64 capability check

On an ARM64 source system, `kexec -l` help should list supported kernel types such as `Image`, `vmlinux`, `uImage` or `vmlinuz`, and ARM64 options including `--append`, `--dtb` and `--initrd`/`--ramdisk` where supported.

Record this output as release evidence because it confirms what kernel formats the installed kexec implementation can load.

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
sudo ./scripts/01-preflight.sh
sudo ./scripts/03-rescue-readiness.sh
```

Before rescue execution, the important result must include:

```text
kexec_tool=PASS
kexec_kernel=PASS
RESCUE_READY=YES
```

Do not run `kexec -e` unless the profile-specific rescue kernel, initramfs, DTB and network configuration have already been built, reviewed and non-destructively proven for that Pi/OS profile.

## kexec lifecycle

```text
kexec -l <kernel> ...  = load a rescue kernel into RAM
kexec -u               = unload/cancel the pending kernel
kexec -e               = transfer execution to the loaded kernel
```

`kexec -e` is the point at which the current CentOS userspace and SSH session disappear.