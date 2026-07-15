# 20260714 SDIO and Wi-Fi driver bring-up

## Result

The Atom Cam 2 SDIO preparation and vendor Wi-Fi driver path were brought up successfully.

The confirmed hardware path became:

```text
T31 SDIO register preparation
-> SDIO vendor 0x007a
-> ATBM603x module
-> ATBM firmware initialization
-> wlan0
```

This proved the Wi-Fi hardware and kernel-driver boundary. It did not yet prove Wi-Fi association, DHCP, mDNS, or SSH.

## Starting boundary

The complete Nerves application root filesystem booted, but no network address appeared.

The early Wi-Fi helper had two problems:

- The required `devmem` command existed at `/sbin/devmem` but was not reliably resolvable from the early `erlinit` pre-run environment.
- Driver fallback logic could select an unrelated Realtek module even after detecting the ATBM vendor ID.

## SDIO register preparation

The vendor boot sequence performs T31 register writes before loading the Wi-Fi module.

BusyBox provided `devmem`, but the early environment did not reliably include `/sbin` in `PATH`.

The helper was changed to use an explicit system path and resolve `/sbin/devmem` directly.

After that change, the SDIO preparation commands completed successfully.

## Vendor identification

The SDIO device reported:

```text
vendor_id=0x007a
```

This vendor requires the ATBM603x driver family.

Once the vendor is known, fallback must remain within that hardware family. Loading `rtl8189ftv.ko` was removed as an invalid fallback.

## Driver module

A kernel-compatible vendor module was obtained from the known-good Atom Cam software and packaged into the Nerves root filesystem:

```text
/lib/modules/atbm603x_wifi_sdio.ko
```

The module had to match the active vendor kernel:

```text
3.10.14__isvp_swan_1.0__
```

The related ATBM firmware and optional configuration files were made available before module loading.

## Confirmed driver result

Boot diagnostics confirmed:

- SDIO preparation completed.
- The ATBM module loaded.
- ATBM firmware initialized.
- The device registered its network interface.
- `wlan0` appeared with the factory MAC address.

The authoritative interface checks on this platform are:

```sh
test -e /sys/class/net/wlan0
ip addr show dev wlan0
```

The included BusyBox `ifconfig` cannot display interface status and should not be used as the sole presence check.

## Rootfs and deployment checks

Two deployment checks were important during this stage:

- Remove stale `rootfs_hack.ext2`, which could override the intended SquashFS.
- Compare the rootfs checksum between the generated payload and the mounted MicroSD card.

These checks prevented stale userspace from being mistaken for a current driver failure.

## Remaining boundary after driver success

Once `wlan0` existed, the remaining path was application-level networking:

```text
VintageNet supervision
-> VintageNet.configure
-> wpa_supplicant
-> Wi-Fi association
-> DHCP
-> mdns_lite
-> nerves_ssh
```

The later investigation found two independent blockers in that path:

- VintageNet's native `if_monitor` crashed because the Linux 3.10 compatibility patch defined `IFA_FLAGS` without expanding `IFA_MAX`.
- `wpa_supplicant` rejected the generated `wps_cred_processing=1` option because the Buildroot binary lacked that WPS configuration support.

Those confirmed fixes are documented in [`20260715-atomcam2-ping-ssh-bringup.md`](20260715-atomcam2-ping-ssh-bringup.md).

## Reusable lessons

- Preserve a known-good kernel while proving userspace and hardware bootstrap.
- Verify the exact final root filesystem before every boot.
- Use explicit command paths in early boot environments.
- Do not cross hardware families in driver fallback logic.
- Treat a precise failure at a later layer as progress.
- Distinguish `wlan0` existence from Wi-Fi association and IP assignment.
