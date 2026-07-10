# AtomCam2 board support

This directory contains board-specific glue that should eventually replace ad-hoc material imported from `atomcam_tools`.

## Initial boot model

```text
U-Boot
  -> Linux 3.10.14 vendor kernel
  -> built-in initramfs /init
  -> mount SD card
  -> switch_root to rootfs_hack.squashfs
  -> erlinit
  -> Nerves release
```

## Principle

Milestone 1 should prove only the boot, network, mDNS, and SSH path. Camera and vendor runtime integration are later milestones.
