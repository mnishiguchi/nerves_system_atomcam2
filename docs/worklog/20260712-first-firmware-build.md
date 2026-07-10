# 20260712 first firmware build

## Goal

Build the first minimal `atomcam2` Nerves firmware image.

The milestone is intentionally small:

- build the custom Nerves system
- build the example Nerves app
- produce an AtomCam2/MIPSEL `.fw`
- prepare for the first SD-card boot test

Camera runtime, RTSP, WebUI, Samba, and vendor app compatibility are outside this milestone.

## Result

The firmware build succeeded.

Firmware file:

```text
examples/atomcam2_nerves_app/_build/atomcam2_dev/nerves/images/atomcam2_nerves_app.fw
```

Observed size:

```text
19M
```

Firmware metadata:

```text
meta-product=atomcam2_nerves_app
meta-description="AtomCam2 first-pass firmware loop"
meta-version=0.1.0
meta-author=nerves_system_atomcam2
meta-platform=atomcam2
meta-architecture=mipsel
```

## Build command

Run from the example app:

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

## Fixes needed to reach this point

The first successful build required these changes:

- remove `nerves_pack` from the example app
- depend directly on `nerves_runtime`, `nerves_ssh`, `mdns_lite`, `vintage_net`, and `vintage_net_wifi`
- remove target-side dependencies that are not needed for Wi-Fi client mode, especially `one_dhcpd`
- use plain `mips32` package metadata instead of `mips32r5`
- keep target GCC flags simple with `-EL -mabi=32`
- add `BR2_PACKAGE_LIBNL=y`
- patch the old Linux 3.10 kernel build to avoid GCC 15 C23 keyword issues
- patch `VintageNet` locally because the Linux 3.10 headers do not define `IFA_FLAGS`

## Notes

The `VintageNet` compatibility patch currently modifies a file under `deps/`, so it must be applied after `mix deps.get`.

This is acceptable for the MVP because it makes the build repeatable without committing vendored dependencies. It should be replaced later with a cleaner dependency strategy.

## Next checkpoint

Burn or install the firmware to a microSD card and confirm the AtomCam2 payload files are present:

```text
factory_t31_ZMC6tiIDQN
rootfs_hack.squashfs
hostname
authorized_keys
nerves-provisioning.conf
```

Then test hardware boot in this order:

```sh
ping nerves.local
ssh nerves.local
```
