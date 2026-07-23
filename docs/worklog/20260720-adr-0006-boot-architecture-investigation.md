# 20260720 ADR 0006 boot architecture investigation

## Purpose

Inspect the current Atom Cam 2 boot and firmware-update paths before
implementing ADR 0006, and determine which rollback architecture is technically
plausible without modifying the protected control kernel.

- Branch: `feat/support-safe-firmware-update-and-rollback`
- ADR revision commit: `e16e4b6`
- Starting `main` commit: `b01df5d`

This worklog records repository findings and design reasoning. It does not
record a completed implementation or physical verification of the proposed
boot-manager handoff.

## Confirmed current boot chain

The supported device boots through:

```text
U-Boot
  -> protected Linux 3.10.14 control kernel
  -> vendor initramfs embedded in that kernel
  -> mount the MicroSD FAT partition
  -> mount rootfs_hack.squashfs
  -> switch_root into the SquashFS
  -> erlinit
  -> Nerves release
```

The protected control-kernel SHA-256 remains:

```text
b50658eac32b57fdcb20383d82a54e6439acd7a3f7e9cb8b43edf4a4b89b03bc
```

`scripts/post-image.sh` requires the kernel image explicitly and rejects any
image whose SHA-256 does not match this value.

## Active initramfs boundary

`board/atomcam2/initramfs/init` reproduces the expected first-stage handoff for
possible future custom-kernel work. It is not the initramfs embedded in the
protected kernel used by the supported system.

The active vendor initramfs selects the fixed FAT-side file:

```text
rootfs_hack.squashfs
```

Therefore, changing the repository-owned initramfs source does not change the
supported physical boot path. Direct slot selection in that source would have
no effect unless the protected kernel were replaced.

The protected kernel must not be replaced, rebuilt, patched, or verified less
strictly as part of ADR 0006.

## Current media and update contract

The current `fwup.conf` defines:

```text
partition 1: FAT boot, firmware, and provisioning files
partition 2: ext2 application data mounted at /data
```

Partition 1 contains the protected kernel and the active application
`rootfs_hack.squashfs`. The current `upgrade` task writes those two files on the
FAT filesystem while preserving partition 2.

This path has been physically verified for host-side updates performed while
the camera is powered down. It is not a safe target-side rollback design
because:

- The running system depends on the same FAT filesystem being modified.
- There is only one application root filesystem.
- An interrupted write can damage the only bootable application image.
- A fully written but defective application has no previous slot to select.

The example application therefore rejects remote fwup uploads and directs the
operator to use the host-side firmware burn workflow.

## Components that cannot select a slot

`rootfs_overlay/usr/bin/atomcam2-pre-run` runs through `erlinit` after the vendor
initramfs has already selected and entered `rootfs_hack.squashfs`. It can create
stable block-device aliases and perform application-root preparation, but it is
too late to choose which root filesystem becomes the running root.

`rootfs_overlay/etc/erlinit.config` invokes that pre-run command immediately
before Erlang starts. It is also too late to provide first-stage slot selection.

Application configuration and `Nerves.Runtime.KV` metadata are available only
after the application root filesystem has already been selected. They cannot
be the authoritative source for pre-boot slot selection.

## Existing physical evidence

Earlier ADR work physically established:

- The protected kernel boots the FAT-side `rootfs_hack.squashfs`.
- Host-side fwup `complete` and `upgrade` workflows function on MicroSD media.
- The protected kernel remains unchanged across those workflows.
- `/data` is a separate ext2 partition.
- `/data` survives graceful reboot and fwup `upgrade`.
- Existing ext2 content is repaired before mounting and is never formatted as a
  fallback.
- Provisioning remains on the FAT partition.

This evidence supports preserving the first-stage vendor contract and keeping
application data independent of firmware activation. It does not prove that a
second root-filesystem handoff is possible.

## Architectures evaluated

### FAT-side A/B files

Example:

```text
rootfs-a.squashfs
rootfs-b.squashfs
```

This is not directly usable because the vendor initramfs selects the fixed
`rootfs_hack.squashfs` filename. Choosing another file would require changing
the protected initramfs or replacing the fixed file during activation.

Keeping both application images on FAT would also retain target-side writes to
the mounted boot filesystem.

### Application A/B partitions selected by the vendor initramfs

Example:

```text
partition 1: boot files
partition 2: application a
partition 3: application b
partition 4: data
```

The partition layout is plausible, but direct selection by the vendor
initramfs is not. The protected initramfs has no repository-controlled logic for
reading rollback state and mounting either application partition.

### Rename-based FAT promotion

Promoting a candidate by renaming or replacing `rootfs_hack.squashfs` would
still modify the mounted FAT filesystem and would expose the fixed boot target
to interrupted activation. It also would not independently provide boot-attempt
accounting or automatic rollback.

### Manual rollback

Retaining a previous image for host-side restoration could improve field
recovery, but it would not satisfy unattended rollback after a failed remote
update. It is insufficient as the primary ADR 0006 design.

### Immutable boot manager with raw application slots

The protected vendor handoff can remain unchanged if
`rootfs_hack.squashfs` becomes a small immutable boot-manager root filesystem.
The boot manager can then select and enter a raw application SquashFS partition.

Conceptually:

```text
vendor initramfs
  -> immutable rootfs_hack.squashfs boot manager
  -> select raw application slot a or b
  -> second root-filesystem handoff
  -> Nerves application
```

This is the only evaluated architecture that preserves the protected kernel,
keeps the vendor filename contract, avoids device-side writes to partition 1,
and permits the running application slot to remain untouched during an update.

## Recommended conditional architecture

After a physical prototype succeeds, use:

```text
MicroSD
├── partition 1
│   ├── FAT
│   ├── protected control kernel
│   ├── immutable rootfs_hack.squashfs boot manager
│   ├── provisioning configuration
│   └── other boot files
├── reserved raw rollback-metadata region
├── partition 2
│   └── raw SquashFS application slot a
├── partition 3
│   └── raw SquashFS application slot b
└── partition 4
    ├── ext2
    └── mounted at /data
```

Device-side application updates would write only the inactive raw application
slot and, after destination verification, the rollback-metadata region.

The protected kernel, boot manager, FAT filesystem, provisioning files, active
application slot, and `/data` would remain unchanged.

The transition from the current two-partition layout should require a host-side
`complete` installation. The first ADR 0006 implementation should not attempt
in-place repartitioning.

## Rollback metadata direction

Slot state must be readable before `/data` is mounted and independent of FAT
filesystem updates. A dedicated raw region is therefore preferred.

The minimum state is:

- Confirmed slot.
- Optional pending slot.
- Remaining pending boot attempts.
- Monotonically increasing generation.
- Firmware identifiers and checksums required to reject mismatched state.
- Record checksum.

Maintain two fixed-size records. Write the next generation to the older or
invalid record while preserving the currently valid record. On boot, select the
valid record with the highest generation.

If neither record is valid, the boot manager must enter an explicit recovery
state instead of guessing.

## Boot-health direction

A pending slot must consume an attempt before the boot manager hands control to
it. A reboot before validation therefore consumes another attempt, and an
exhausted candidate returns to the confirmed slot.

Application validation should require:

- OTP application startup.
- `/data` mounted read-write.
- Expected firmware and slot metadata.
- Required network subsystem initialization without an internal failure.
- A defined stabilization period.

External network reachability should not be required unless the product
contract explicitly depends on it.

Boot-attempt accounting covers failures that reboot. A candidate that hangs
indefinitely requires an independent reset mechanism. The repository's future
kernel defconfig contains `CONFIG_JZ_WDT=y`, but that does not prove that the
protected kernel exposes a usable watchdog or that its behavior is suitable.
Physical verification is required.

## Persistent-data compatibility

Firmware rollback does not roll back `/data`.

The initial policy should require firmware updates to remain backward-compatible
with the existing `/data` format. Destructive or irreversible migrations are
outside ADR 0006 and require a separate design before use.

Moving `/data` from partition 2 to partition 4 is a media-layout integration
change. It must preserve ADR 0005 initialization, repair, persistence, and
factory-reset behavior.

## Prototype gates

Before implementing A/B update logic, prove on physical hardware that:

- The protected-kernel SHA-256 remains unchanged.
- The vendor initramfs enters the boot-manager `rootfs_hack.squashfs`.
- The boot manager discovers the correct MicroSD block device and application
  partition.
- The protected kernel mounts a raw SquashFS application partition.
- The boot manager performs a second root-filesystem handoff successfully.
- `/dev`, `/proc`, `/sys`, and the FAT mount remain usable after the handoff.
- `erlinit` and the Nerves release start from the application partition.
- `/data` initializes, repairs, and mounts under the ADR 0005 policy.
- Graceful reboot and poweroff remain reliable.
- A hardware watchdog or equivalent reboot mechanism is available and behaves
  predictably.

Failure of a foundational gate must stop implementation and trigger another ADR
revision. It must not trigger a protected-kernel change by default.

## Open questions

- Which exact mounts must be moved or rebound during the second handoff?
- Can the protected kernel mount raw SquashFS reliably from both candidate
  partition offsets?
- What minimal userspace and tools must the boot manager contain?
- How should the boot manager report recovery when neither application slot is
  usable?
- Where should the raw metadata region begin, and what size and alignment are
  safe?
- What fixed application-slot size and minimum MicroSD capacity should be
  supported?
- Does the protected kernel expose a usable `/dev/watchdog`?
- What are the watchdog timeout, close, and reboot semantics?
- Can fwup select the inactive destination safely, or should a checked wrapper
  dispatch internal slot-specific tasks?
- How should the application obtain the authoritative running-slot identity?

## Staged work

1. Record and review the corrected architecture.
2. Build a single-slot boot-manager prototype without rollback metadata.
3. Verify the second root-filesystem handoff on physical hardware.
4. Add redundant raw slot metadata and manual slot selection.
5. Add inactive-slot writing and destination verification.
6. Add standard status, validate, revert, prevent-revert, and factory-reset
   operations.
7. Add bounded boot attempts, application health confirmation, and watchdog
   recovery.
8. Run the complete physical failure matrix.
9. Enable remote fwup only after ADR 0006 and ADR 0007 acceptance requirements
   pass.

## Conclusion

The existing repository does not control the initramfs embedded in the
protected kernel, so ADR 0006 cannot implement slot selection there.

The recommended path is an immutable `rootfs_hack.squashfs` boot manager that
performs a second handoff into raw A/B application partitions. This architecture
remains conditional until a minimal physical prototype proves the handoff and
watchdog assumptions.

No A/B metadata, update, or remote-upload implementation should begin before
that prototype succeeds.

## Prototype boot handoff and data persistence verification

The physical handoff prototype was verified on an Atom Cam 2 using the protected vendor control kernel.

Verified boot path:

```text
protected vendor kernel
-> vendor initramfs
-> immutable boot-manager SquashFS
-> application SquashFS on partition 2
-> pivot_root
-> old boot-manager root detached
-> Nerves release
```

The boot manager dynamically discovered the FAT boot mount, moved the required kernel filesystems into the application root, completed `pivot_root`, unmounted the old root, and started `/sbin/init`.

Early boot progress was captured through FAT reports and raw stage breadcrumbs written to the reserved beginning of prototype partition 3.

### Data partition initialization

A complete installation writes the following one-time authorization marker to the FAT partition:

```text
atomcam2-data-init
format-if-missing
```

On first boot, `atomcam2-pre-run`:

- detected that partition 3 did not contain ext2
- formatted it as ext2 with label `ATOMCAM2_DATA`
- mounted it read-write at `/data`
- verified write access
- removed the initialization marker

The resulting report contained:

```text
stage=pre_run_complete
data_status=formatted_ext2_mounted
data_writable=1
data_init_requested=0
```

### Destructive raw write finding

The initial prototype used:

```text
raw_memset(${DATA_PART_OFFSET}, 256, 0xff)
```

The count was interpreted as 256 sectors rather than 256 bytes. This erased 131072 bytes and destroyed the ext2 superblock at byte 1024.

The destructive operation was removed. The smoke test now rejects any `raw_memset` targeting `DATA_PART_OFFSET`.

### Existing filesystem preservation

A preservation probe was written and synchronized:

```text
/data/adr0006-preservation-probe
preserve across complete
```

Its SHA-256 before the corrected complete installation was:

```text
6c27f92a01ddbbd369731e1020ab5f268499c30634b1ef126e8251fa76c8f78c
```

After installing the corrected firmware with the `complete` task:

- partition 3 remained ext2
- the `ATOMCAM2_DATA` label remained
- the partition table remained unchanged
- the probe remained present
- the probe SHA-256 remained identical

After reboot, the report contained:

```text
stage=pre_run_complete
data_status=existing_ext2_mounted
data_writable=1
data_init_requested=0
```

The runtime mount was:

```text
/dev/mmcblk0p3 /data ext2 rw,relatime,errors=continue
```

The initialization marker was removed after successful mounting.

### Verified firmware

```text
Nickname: mimic-lonely
UUID: 898ac04d-2f4b-57a7-22a9-daddbea2fd6f
Version: 0.1.0
Platform: atomcam2
```

### Result

The prototype now proves:

- reliable handoff from the immutable boot manager to application partition 2
- detachment of the old boot-manager root
- explicit first-boot authorization before formatting partition 3
- automatic read-write mounting of `/data`
- preservation of an existing healthy `/data` filesystem across complete installation

The prototype does not yet implement A/B slot selection, rollback metadata, confirmation, attempt counting, or watchdog-driven rollback.
