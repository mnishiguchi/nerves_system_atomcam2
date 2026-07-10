# AtomCam2 initramfs

This directory contains the text portion of the first-pass AtomCam2 initramfs.

The important `atomcam_tools` boot pattern kept here is the handoff from the
vendor-named kernel image to `rootfs_hack.squashfs` on the FAT partition. The
initramfs must contain a tiny shell environment, mount the SD card, mount the
Nerves squashfs, move the FAT mount to `/media/mmc`, and then `switch_root`.

Current scope:

- mount the first SD-card partition as VFAT
- locate `rootfs_hack.squashfs`
- mount it as the new root filesystem
- move `dev`, `proc`, `sys`, and the SD-card mount into the new root
- `switch_root` into `/sbin/init`

Deferred from the first loop:

- exFAT second-partition support
- on-device update unpacking
- rootfs size validation
- vendor recovery paths
