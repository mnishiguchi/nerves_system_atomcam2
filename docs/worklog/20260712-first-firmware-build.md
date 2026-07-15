# 20260712 first firmware build

## Status

The first minimal `atomcam2` Nerves firmware built successfully. This was a build milestone only; hardware ping and SSH were verified later on July 15, 2026.

See [`20260715-atomcam2-ping-ssh-bringup.md`](20260715-atomcam2-ping-ssh-bringup.md) for the completed network milestone.

## Goal

- Build the custom Nerves system
- Build the example Nerves application
- Produce an AtomCam2 MIPSEL firmware artifact
- Prepare the flat MicroSD payload for hardware testing

Camera runtime and vendor application compatibility were outside this stage.

## Result

The firmware build succeeded with metadata identifying:

```text
meta-product=atomcam2_nerves_app
meta-platform=atomcam2
meta-architecture=mipsel
```

The initial artifact was approximately 19 MB.

## Build command used at this stage

```sh
cd examples/atomcam2_nerves_app
direnv allow
mix deps.get
../../scripts/patch-vintage-net-linux-3.10.sh
mix firmware
```

The later repository workflow standardized this through:

```sh
./scripts/build-firmware-log.sh
```

## Build fixes established

The first successful build required:

- Direct dependencies on `nerves_runtime`, `nerves_ssh`, `mdns_lite`, `vintage_net`, and `vintage_net_wifi`
- Removal of unrelated Wi-Fi access-point dependencies from the MVP
- Conservative MIPS32 native build flags
- `BR2_PACKAGE_LIBNL=y`
- A GNU89 compatibility patch for the Linux 3.10 kernel source
- An initial Linux 3.10 compatibility patch for VintageNet

The initial VintageNet patch was later corrected because defining `IFA_FLAGS` without updating `IFA_MAX` caused a native runtime crash. The final correction is documented in the July 15 bring-up report.

## Outcome

This build proved that the repository could produce a complete Nerves firmware artifact. It did not yet prove:

- Dynamic userspace compatibility on the Ingenic T31
- Correct boot payload selection
- Vendor Wi-Fi driver startup
- Wi-Fi association
- DHCP, mDNS, or SSH

Those boundaries were investigated in later worklogs.
