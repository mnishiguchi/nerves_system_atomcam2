# 20260713 runtime prerequisites for the first network test

## Status

This is an intermediate checklist of changes that moved the system from a build artifact toward a bootable Nerves userspace. It is not the final root-cause report for ping and SSH.

Later confirmed blockers are documented in:

- [`20260713-atomcam2-toolchain-dsp-ase-investigation.md`](20260713-atomcam2-toolchain-dsp-ase-investigation.md)
- [`20260714-sdio-wifi-driver-bring-up.md`](20260714-sdio-wifi-driver-bring-up.md)
- [`20260715-atomcam2-ping-ssh-bringup.md`](20260715-atomcam2-ping-ssh-bringup.md)

## Changes introduced during this stage

- Added the musl loader required by initramfs executables.
- Enabled the T31 MMC1 SDIO controller used by the Wi-Fi device.
- Enabled gzip-compatible SquashFS support for the generated root filesystem.
- Restored the known-good Atom Cam 2 kernel command line.
- Mounted vendor system and configuration partitions read-only for hardware bootstrap data.
- Reused the vendor SDIO preparation and Wi-Fi module-loading sequence.
- Restored the factory Wi-Fi MAC address before network configuration.
- Added a bounded wait for `wlan0`.
- Kept the known-good vendor kernel as a temporary override so userspace could be tested independently from the custom-kernel work.

## What this stage established

These changes created a testable boot path, but the absence of `nerves.local` still did not identify the failing layer.

The subsequent investigation separately proved:

```text
boot and rootfs
-> dynamic userspace
-> Erlang release
-> SDIO and vendor driver
-> VintageNet native monitor
-> wpa_supplicant configuration
-> DHCP, mDNS, and SSH
```

## Test order retained

The useful verification order remains:

1. Confirm the active root filesystem and `/sbin/init`.
2. Confirm the Erlang release under `/srv/erlang`.
3. Confirm SDIO preparation and vendor module loading.
4. Confirm `wlan0` through `/sys/class/net/wlan0` or `ip`.
5. Confirm VintageNet configuration.
6. Confirm Wi-Fi association and DHCP by direct IP.
7. Confirm `nerves.local`.
8. Confirm SSH public-key access.
