# AtomCam2 board support

This directory contains board-specific glue for the Atom Cam 2 Nerves system.

## Supported boot model

The supported physical system currently uses the verified control kernel originally obtained from `atomcam_tools`. That kernel includes the active vendor initramfs.

```text
U-Boot
  -> verified Linux 3.10.14 control kernel
  -> built-in vendor initramfs /init
  -> mount SD card
  -> switch_root to rootfs_hack.squashfs
  -> erlinit
  -> Nerves release
```

The initramfs source in this directory documents and reproduces the required handoff for future custom-kernel work. It is not the active initramfs while the supported firmware uses the protected control kernel.

## Principle

Keep board-specific code limited to confirmed Atom Cam 2 requirements. The supported Nerves system owns the root filesystem, runtime, provisioning, and firmware workflow; it does not import the general `atomcam_tools` userland or update mechanism.

ADR 0008 may add an optional compatibility service that reads the protected
vendor camera filesystems. That service must remain disabled by default, keep
internal flash read-only, use private writable state under `/data`, and leave
Nerves in control of networking, the watchdog, updates, rollback, and recovery.
