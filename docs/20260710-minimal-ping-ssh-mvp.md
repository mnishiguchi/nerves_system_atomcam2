# Minimal ping and SSH MVP

## Purpose

This document is the only project note to keep for the first Atom Cam 2 Nerves bring-up.

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

## Expected SD-card payload

The microSD card should contain these files at the top level:

```text
factory_t31_ZMC6tiIDQN
rootfs_hack.squashfs
hostname
authorized_keys
```

`hostname` should contain:

```text
nerves
```

## Build host checks

Run this from the system repository root before testing on hardware:

```sh
./scripts/smoke-check.sh
```

Package the SD-card payload:

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

When testing fails, record only the earliest failing checkpoint:

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
