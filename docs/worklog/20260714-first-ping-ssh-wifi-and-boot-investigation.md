# 20260714 AtomCam2 boot and rootfs investigation

## Status

This worklog records the confirmed boot and root-filesystem findings that narrowed the remaining problem to Wi-Fi and application networking.

It intentionally omits most provisional hypotheses from the original investigation. The final network result is documented in [`20260715-atomcam2-ping-ssh-bringup.md`](20260715-atomcam2-ping-ssh-bringup.md).

## Goal

Prove each layer before diagnosing `nerves.local`:

```text
MicroSD payload
-> kernel and initramfs
-> rootfs selection
-> switch_root
-> /sbin/init
-> Erlang release
-> hardware bootstrap
-> Wi-Fi and network services
```

## Confirmed boot path

The first reliable userspace test kept the already proven `atomcam_tools` kernel and replaced the userspace with the Nerves root filesystem.

This hybrid approach isolated the Nerves userspace from the separate custom-kernel size and boot work.

The active boot path was:

```text
factory_t31_ZMC6tiIDQN
-> vendor initramfs
-> /media/mmc/rootfs_hack.squashfs
-> loop-mounted SquashFS
-> switch_root
-> Nerves /sbin/init
-> erlinit
-> Erlang release
```

## Application-merged root filesystem

A base Nerves system image was insufficient because it did not contain the application release under:

```text
/srv/erlang
```

The firmware post-processing step preserved the final application-merged image as:

```text
examples/atomcam2_nerves_app/_build/atomcam2_prod/nerves/images/rootfs_hack.final.squashfs
```

The flat SD payload copied this image as:

```text
rootfs_hack.squashfs
```

Before hardware testing, extracting the image and confirming `/srv/erlang` became a required verification step.

## Stale rootfs precedence

An older diagnostic file named:

```text
rootfs_hack.ext2
```

could take precedence over the newer SquashFS payload.

This produced misleading tests in which a correct build was installed but the camera booted an older diagnostic userspace.

The cleanup rule became:

- Remove stale `rootfs_hack.ext2` files.
- Verify the checksum of `rootfs_hack.squashfs` after copying it to the card.
- Confirm the application release inside the exact image installed on the card.

## Initramfs boundary

The known-good vendor kernel included its own active initramfs.

Changes to the repository's custom initramfs were therefore not evidence about the active hybrid boot path unless the custom kernel was also being tested.

This distinction prevented inactive initramfs changes from being mistaken for runtime fixes.

## Confirmed userspace progress

FAT-partition breadcrumbs and rootfs inspection confirmed:

- The MicroSD card mounted.
- The SquashFS root filesystem mounted through a loop device.
- `switch_root` completed.
- Nerves `/sbin/init` started.
- The application release existed under `/srv/erlang`.
- The Erlang VM started far enough to run the application network worker.

At this point, missing ping and SSH no longer indicated a general boot failure.

## Wi-Fi hardware boundary

The SDIO device reported vendor ID:

```text
0x007a
```

This identifies the ATBM603x family used by the camera. The correct driver is:

```text
atbm603x_wifi_sdio.ko
```

A Realtek fallback was invalid after the vendor had been identified.

The detailed SDIO initialization, module selection, and `wlan0` result are documented in [`20260714-sdio-wifi-driver-bring-up.md`](20260714-sdio-wifi-driver-bring-up.md).

## Findings that were not final blockers

Several observations were useful during diagnosis but were not the final reasons ping and SSH failed:

- Optional ATBM text configuration files were not sufficient by themselves to explain the failure.
- Missing `/data/.mac.info` was not proof that the Wi-Fi device could not start; the factory MAC could be restored through the bootstrap logic.
- A missing `nerves.local` name could not distinguish boot, Wi-Fi, DHCP, or mDNS failures.
- BusyBox `ifconfig` on this image could not display interface status and produced a false negative.
- Repository initramfs changes were inactive while the known-good vendor kernel remained in use.

## Outcome

By the end of this investigation, the confirmed boundary was:

```text
boot and Nerves userspace: working
application release: working
remaining work: SDIO driver, VintageNet, Wi-Fi association, DHCP, mDNS, SSH
```

The next worklogs narrowed those layers further until ping and SSH succeeded.
