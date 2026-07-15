# 20260710 minimal ping and SSH MVP plan

## Status

This document records the initial plan for the first Atom Cam 2 Nerves milestone.

The milestone was completed on July 15, 2026. See [`20260715-atomcam2-ping-ssh-bringup.md`](20260715-atomcam2-ping-ssh-bringup.md) for the verified result and confirmed blockers.

## Goal

Prove that an Atom Cam 2 can boot a minimal Nerves system from a MicroSD card and become reachable over Wi-Fi:

```sh
ping nerves.local
ssh nerves@nerves.local
```

Everything unrelated to basic boot and network access was intentionally deferred.

## Scope

The first milestone required:

- An SD-card boot payload
- Kernel and initramfs handoff
- Read-only root filesystem mounting
- `erlinit` and the Erlang release
- Vendor Wi-Fi hardware preparation
- `wlan0` configuration through VintageNet
- DHCP
- `mdns_lite` advertisement as `nerves.local`
- `nerves_ssh` public-key access
- Small FAT-partition diagnostics for early bring-up

Camera capture, RTSP, WebUI, Samba, and vendor application compatibility were excluded.

## Expected SD-card payload

The FAT partition contains:

```text
factory_t31_ZMC6tiIDQN
rootfs_hack.squashfs
hostname
authorized_keys
nerves-provisioning.conf
```

`hostname` contains:

```text
nerves
```

The root filesystem must be the application-merged SquashFS containing `/srv/erlang`, not only the base Nerves system image.

## Build and package workflow

Run repository checks and the firmware wrapper from the repository:

```sh
./scripts/check-prereqs.sh
./scripts/smoke-check.sh
./scripts/build-firmware-log.sh
```

The build wrapper applies the required system checks and produces the flat SD payload under the example application's Nerves images directory.

Before installing the payload, verify it:

```sh
./scripts/atomcam2-check-sd-payload.sh /path/to/atomcam2-sd
```

Install it to the mounted FAT partition:

```sh
./scripts/install-sd-files.sh \
  --source /path/to/atomcam2-sd \
  --mount /path/to/mounted/sd \
  --force
```

## Hardware checkpoints

The intended checkpoint order was:

```text
U-Boot loads factory_t31_ZMC6tiIDQN
kernel starts
initramfs starts
MicroSD is detected
rootfs_hack.squashfs is mounted
switch_root runs
erlinit starts
Erlang release starts
vendor Wi-Fi driver loads
wlan0 appears
Wi-Fi association succeeds
DHCP succeeds
mdns_lite advertises nerves.local
nerves_ssh accepts the public key
```

Host-side verification:

```sh
getent ahostsv4 nerves.local
ping -c 4 nerves.local
ssh nerves@nerves.local
```

Direct IP connectivity should be checked before treating an mDNS failure as a general network failure.

## Diagnostic boundary

When a boot failed, the useful rule was to record the earliest failing checkpoint rather than infer the cause from the absence of `nerves.local`.

Collect FAT-partition diagnostics with:

```sh
./scripts/collect-boot-report.sh --mount /path/to/mounted/sd
```

A minimal record should include:

```text
Date:
Image source:
SD payload verified: yes/no
Serial console available: yes/no
Last successful checkpoint:
First failing checkpoint:
Relevant evidence:
Next layer to test:
```
