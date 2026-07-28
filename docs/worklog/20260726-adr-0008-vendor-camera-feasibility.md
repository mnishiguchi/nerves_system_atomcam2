# 20260726 ADR 0008 vendor camera feasibility

## Status

The read-only feasibility investigation is complete.

Result:

```text
vendor runtime foundation: feasible
stock vendor startup: unsafe
manual camera start: gated
recording and NAS work: not started
```

This is a conditional go for a deliberately isolated Phase 2 compatibility
service. It is not evidence that mobile viewing or recording already works.

## Scope and method

The device ran released `nerves_system_atomcam2` v0.2.0. The repository base was
commit `ddcedef`.

Inspection used NervesSSH and read-only kernel, procfs, sysfs, mount, filesystem,
ELF, and module metadata. No vendor process was started. No camera module was
loaded. No internal flash partition was erased, written, remounted, or otherwise
modified. Sensitive vendor configuration contents were not collected.

The public `atomcam_tools` source at commit
`313048b4d652b0058271ffa42de1289e9d5d08ee` was inspected to identify its
startup, chroot, recording-completion, and NAS behavior.

## Live storage inventory

The protected kernel exposes eight internal SPI-NOR partitions:

```text
mtd0  boot      256 KiB
mtd1  kernel   1984 KiB
mtd2  rootfs   3904 KiB
mtd3  app      3904 KiB
mtd4  kback    1984 KiB
mtd5  aback    3904 KiB
mtd6  cfg       384 KiB
mtd7  para       64 KiB
```

The active vendor initramfs had already prepared these read-only mounts before
the Nerves rootfs handoff:

```text
/dev/loop1      /atom          squashfs  ro
/dev/mtdblock3  /atom/system   squashfs  ro
/dev/mtdblock6  /atom/configs  jffs2     ro
```

The root image backing `/atom` was `/tmp/atom_root.squashfs`. The original
vendor application and configuration partitions therefore do not need to be
made writable for compatibility work.

The Nerves data partition was:

```text
/dev/mmcblk0p4  /data  ext2  rw
```

It had approximately 13.5 GiB free. That is ample for a bounded outage spool,
but not a 20-day continuous-recording archive. Long-term retention belongs on
the NAS.

## Vendor runtime inventory

The vendor application filesystem contains:

- `iCamera_app`, `assis`, `hl_client`, `ver-comp`, and `dongle_app`;
- the uClibc loader and runtime;
- camera, local SDK, MP4, crypto, P2P, and audio libraries;
- GC2053 sensor configuration;
- ISP, sensor, audio, VPU, PWM, speaker, and other board modules.

The camera-related modules report the exact running kernel release in their
vermagic:

```text
3.10.14__isvp_swan_1.0__
```

This includes:

- `tx-isp-t31.ko`
- `sensor_gc2053_t31.ko`
- `audio.ko`
- `avpu.ko`
- `sinfo.ko`
- `sample_pwm_core.ko`
- `sample_pwm_hal.ko`
- `speaker_ctl.ko`

The executable ABI is distinct from Nerves:

```text
ELF 32-bit little-endian MIPS32r2
interpreter /lib/ld-uClibc.so.0
hard-float ABI
```

The runtime must therefore use the vendor root and libraries. Direct execution
against the Nerves musl root is not viable. A chroot rooted at `/atom` is the
smallest conventional compatibility mechanism.

The v0.2.0 BusyBox did not include the `chroot` applet. The feasibility branch
enables it for the next system build.

## Resources

The live kernel command line reserves the vendor camera memory region:

```text
mem=92M@0x0 rmem=36M@0x5c00000
```

Observed Linux memory before starting any vendor process:

```text
MemTotal:       87700 KiB
MemFree:        about 11200 KiB
Buffers:        about 12700 KiB
Cached:         about 28500 KiB
BEAM VmRSS:     about 34500 KiB
Swap:           0
```

Roughly 52 MiB was free or reclaimable, so a bounded manual camera trial is
reasonable. This does not prove steady-state memory safety. `atomcam_tools`
documents using MicroSD swap for its much larger service set; this project must
measure the minimal vendor process set before considering unattended startup.

System V message queues and shared memory are available. No existing vendor
process or camera device node was present during the probe.

## Why the stock startup is unsafe

The vendor `app_init.sh` does more than initialize the camera. It:

- loads unrelated exFAT, USB Ethernet, MMC, and Wi-Fi modules;
- starts its own Wi-Fi selection and configuration;
- writes SoC registers through `devmem`;
- starts factory and USB helpers;
- starts `assis`, `hl_client`, `iCamera_app`, and `dongle_app`; and
- assumes writable `/configs`, `/tmp`, and `/media/mmc` paths.

Reusing it would conflict with Nerves ownership of networking, storage, and
recovery.

The public `atomcam_tools` implementation also avoids using the internal config
partition as writable runtime state. It copies protected configuration into an
ext2 image on MicroSD and mounts that copy at `/atom/configs`. The equivalent
Nerves design should keep a private copy under `/data`.

## Watchdog conflict

Nerves `heart` held the real hardware watchdog:

```text
/proc/245/fd/3 -> /dev/watchdog0
```

Static inspection of `assis` confirmed that it links
`liblocalsdk_watchdog.so` and calls the vendor open, timeout, feed, and close
watchdog functions. Its strings also include paths that kill `iCamera_app` and
reboot the device. `iCamera_app` contains its own assistant/watchdog IPC logic.

Starting stock `assis` against the real `/dev/watchdog` would either fail to
claim the single-open watchdog or compete with the Nerves recovery mechanism.
Disabling Nerves `heart` is not acceptable.

Phase 2 must determine whether `iCamera_app` remains healthy with `assis`
omitted or prevented from seeing the hardware watchdog. If not, stop and make a
separate minimal compatibility decision. Do not import the broad
`atomcam_tools` preload layer merely to get past this gate.

## Compatibility layout constraints

The existing Nerves `/tmp` is mounted `noexec`, while the vendor runtime expects
to execute helpers below `/tmp`. The compatibility service should instead
mount a private size-bounded tmpfs at `/atom/tmp` with the required execution
semantics.

The chroot should receive only curated mounts:

```text
/atom/system   protected vendor application, read-only
/atom/configs  private copy from /data, read-write
/atom/tmp      private bounded tmpfs
/atom/proc     procfs
/atom/sys      required sysfs view
/atom/dev      required device view without the real watchdog
/atom/media    local recording spool mapping under /data
```

Mount operations are visible to the host mount namespace, so startup and stop
must be ordered, idempotent, and restricted to paths below `/atom`.

## Recording and NAS observations

The standard vendor recorder writes temporary MP4 data and moves each completed
one-minute segment into `/media/mmc/record`.

`atomcam_tools` replaces the vendor `mv` command to detect that completion
boundary, then combines SD-card policy, CIFS copying, webhooks, naming, and
scheduling. ADR 0008 keeps only the completion boundary. Nerves should own the
local spool and a separate exporter.

The active protected kernel did not list either `nfs` or `cifs` in
`/proc/filesystems`, and no matching modules were available in the running
rootfs. The repository's future custom-kernel defconfig enabling NFS is not
evidence about the protected kernel in the supported v0.2.0 boot path.

Phase 4 must therefore prove a NAS client mechanism separately. This does not
block the manual vendor camera runtime, but it blocks assuming that an NFS mount
will work on v0.2.0.

## Implemented probe

The feasibility branch adds:

```text
atomcam2-vendor-camera precheck
```

The command only reads mount, file, module, process, memory, IPC, watchdog, and
filesystem capability state. It does not mount filesystems, copy
configuration, load modules, or start processes.

Exit results are:

```text
0  ready for a manual camera start
1  a required platform capability is missing or unsafe
2  the foundation is present but explicit safety gates remain
```

During this milestone, the expected result is `2`. `start`, `status`, and
`stop` are intentionally unavailable.

The exact new script was also executed in memory over NervesSSH, without
installing it on the device. Against released v0.2.0 it reported:

```text
summary failures=1 gates=3 warnings=1
result=blocked
```

The single platform failure was the expected missing `chroot` applet. The three
gates were watchdog isolation, the private `/data` configuration copy, and the
manual memory/mobile-viewing trial. The one warning was missing NFS client
support.

The feasibility branch then passed:

- the full `mix smoke` system suite;
- the example application's 23 host tests;
- a local Nerves system rebuild; and
- SquashFS inspection confirming executable
  `/usr/bin/atomcam2-vendor-camera` and BusyBox `/usr/sbin/chroot`.

The rebuilt firmware was not uploaded. Preserving the read-only device scope
keeps firmware installation and process startup in the Phase 2 manual-runtime
milestone.

## Phase 2 entry criteria

Before a manual camera start:

1. Build and install a firmware containing the precheck and `chroot`.
2. Confirm the precheck has no platform failures.
3. Create a mode-0700 private configuration copy under `/data` without logging
   its contents.
4. Prepare a private bounded tmpfs and curated chroot mounts.
5. Ensure vendor processes cannot open the real watchdog, restart Wi-Fi, write
   internal flash, or reboot the device.
6. Define the minimum camera module and process sequence.

The manual trial must then prove:

- standard Atom mobile-application live viewing;
- stable Nerves Wi-Fi and SSH;
- continued Nerves `heart` ownership of `/dev/watchdog0`;
- BEAM and vendor process memory over a meaningful interval;
- clean vendor-process shutdown;
- cleanup of compatibility mounts and IPC; and
- continued OTA, rollback, and recovery access after failure.
