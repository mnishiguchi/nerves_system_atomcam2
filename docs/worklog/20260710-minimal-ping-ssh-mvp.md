# Minimal ping and SSH MVP

## Purpose

This document is the main project note for the first Atom Cam 2 Nerves bring-up.

The current goal is deliberately small:

```sh
ping nerves.local
ssh nerves.local
```

Everything else should wait until these two commands work reliably on real hardware.

## Scope

Keep only what is needed for the first reachable Nerves system:

- SD-card boot payload
- kernel and initramfs handoff
- read-only root filesystem mount
- `erlinit` startup
- Wi-Fi interface bring-up
- DHCP on `wlan0`
- `mdns_lite` hostname announcement as `nerves.local`
- `nerves_ssh` access
- small boot breadcrumbs for debugging

Plain target-side shell helpers live in `rootfs_overlay`. Keep them there unless a future milestone needs a compiled Buildroot package.

## Expected SD-card payload

The microSD card should contain these files at the top level:

```text
factory_t31_ZMC6tiIDQN
rootfs_hack.squashfs
hostname
authorized_keys
nerves-provisioning.conf
```

`hostname` should contain:

```text
nerves
```

## Build host checks

Run this from the system repository root before testing on hardware:

```sh
./scripts/check-prereqs.sh
./scripts/smoke-check.sh
```

## Firmware build

Run firmware builds from the example app because its `.envrc` sets `MIX_TARGET=atomcam2` and Wi-Fi environment variables:

```sh
cd examples/atomcam2_nerves_app
direnv allow
mix deps.get
../../scripts/patch-vintage-net-linux-3.10.sh
mix firmware
```

Expected success:

```text
Firmware built successfully
```

Verify firmware metadata:

```sh
fwup -m -i _build/atomcam2_dev/nerves/images/atomcam2_nerves_app.fw
```

Expected metadata includes:

```text
meta-platform=atomcam2
meta-architecture=mipsel
```

## Build notes

The example app avoids `nerves_pack` for this phase.

`nerves_pack` is convenient, but it pulls in `vintage_net_direct` and `one_dhcpd`. Those are not needed for Wi-Fi client mode and caused native compilation issues during the current MIPSEL bring-up.

The example app depends directly on:

- `nerves_runtime`
- `nerves_ssh`
- `mdns_lite`
- `vintage_net`
- `vintage_net_wifi`

The current build also needs a local compatibility patch for `VintageNet` because the Linux 3.10 headers used for this bring-up do not define `IFA_FLAGS`.

Run this after `mix deps.get`:

```sh
../../scripts/patch-vintage-net-linux-3.10.sh
```

This is an MVP build shim. Later, replace it with a cleaner dependency patch, fork, or upstream-compatible fix.

## SD-card payload packaging

If using the flat SD-card payload helper directly, package the SD-card payload from the repository root:

```sh
./scripts/atomcam2-package-flat-sd.sh \
  --images-dir target/images \
  --output-dir target/atomcam2-sd \
  --hostname nerves \
  --authorized-keys "$HOME/.ssh/id_ed25519.pub"
```

Verify the payload shape:

```sh
./scripts/atomcam2-check-sd-payload.sh target/atomcam2-sd
```

The packaging helper copies `target/images/nerves-provisioning.conf` when it exists. It is also safe to edit `target/atomcam2-sd/nerves-provisioning.conf` directly before copying the files to the SD card.

Install the files to a mounted FAT partition:

```sh
./scripts/install-sd-files.sh \
  --source target/atomcam2-sd \
  --mount /path/to/mounted/sd \
  --dry-run

./scripts/install-sd-files.sh \
  --source target/atomcam2-sd \
  --mount /path/to/mounted/sd \
  --force
```

## Hardware success checkpoints

The first useful serial-console checkpoints are:

```text
U-Boot loads factory_t31_ZMC6tiIDQN
kernel starts
initramfs starts
SD card is detected
rootfs_hack.squashfs is mounted
switch_root runs
erlinit starts
wlan0 appears
DHCP succeeds
mdns_lite advertises nerves.local
nerves_ssh starts
```

From the host machine, test in this order:

```sh
ping nerves.local
ssh nerves.local
```

Do not debug SSH until `ping nerves.local` works.

## Deferred work

Do not add nonessential platform features during this phase. The first hardware iteration should answer only one question:

> Can Atom Cam 2 boot a minimal Nerves system and become reachable over the network?

After that is proven, create new dated docs for the next milestone.

## Debug note template

When testing fails, collect the FAT-partition breadcrumbs first:

```sh
./scripts/collect-boot-report.sh --mount /path/to/mounted/sd
```

Then record only the earliest failing checkpoint:

```text
Date:
Image source:
SD-card payload checked: yes/no
Serial console available: yes/no
Last successful checkpoint:
First failing checkpoint:
Relevant log excerpt:
Next suspected layer:
```
