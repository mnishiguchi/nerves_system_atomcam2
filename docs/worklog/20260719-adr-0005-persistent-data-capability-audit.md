# 20260719 ADR 0005 persistent data capability audit

## Purpose

Inspect the running Atom Cam 2 without modifying the MicroSD card and determine
which filesystem and device-path assumptions are safe for ADR 0005.

## Protected kernel

The kernel file on the writable boot filesystem matched the required SHA-256:

```text
b50658eac32b57fdcb20383d82a54e6439acd7a3f7e9cb8b43edf4a4b89b03bc
```

The running kernel reported:

```text
Linux version 3.10.14__isvp_swan_1.0__
```

The protected kernel and its verification were not changed.

## Current MicroSD layout

`/proc/partitions` reported one MicroSD device and one partition:

```text
179        0   15267840 mmcblk0
179        1   15266816 mmcblk0p1
```

The relevant mounts were:

```text
/dev/mmcblk0p1 /media/mmc vfat rw
/dev/mmcblk0p1 /boot vfat ro
/dev/loop0 / squashfs ro
```

No `/dev/rootdisk0` alias or second MicroSD partition was present. The current
single FAT partition occupies nearly all media capacity, so the ADR 0005 layout
transition requires a fwup `complete` installation rather than an in-place
firmware upgrade.

## Protected-kernel filesystem support

`/proc/filesystems` reported these relevant filesystems:

```text
ext2
squashfs
vfat
exfat
jffs2
```

Ext4 and F2FS were not reported.

Ext2 is therefore the only confirmed filesystem that provides Linux filesystem
semantics on an ordinary MicroSD block partition without changing the protected
kernel. JFFS2 applies to raw flash devices, SquashFS is read-only, and FAT-family
filesystems do not provide the intended `/data` semantics.

## Current userspace tools

The current root filesystem did not provide:

```text
mkfs.ext2
mke2fs
e2fsck
fsck.ext2
tune2fs
dumpe2fs
resize2fs
blkid
```

The BusyBox `lsblk` applet was present, but it did not support util-linux-style
column-selection options.

## Decision evidence

Use ext2 for the first ADR 0005 implementation, subject to physical
power-interruption and recovery testing.

Before changing `fwup.conf`:

- Add the e2fsprogs formatting and checking tools to the root filesystem.
- Verify that `mkfs.ext2`, `e2fsck`, and `fsck.ext2` are present in a built
  firmware.
- Establish a stable application-partition path derived from the boot device
  rather than depending only on MicroSD enumeration.

Ext2 has no journal. If interrupted-write and recovery tests show that its
behavior is unsuitable, stop implementation and handle any protected-kernel
change through a separate decision.

## Ext2 userspace tooling verification

The system was rebuilt with `BR2_PACKAGE_E2FSPROGS=y` and assembled into the
example application firmware using the verified Atom Cam 2 control kernel.

Build verification confirmed that the final merged SquashFS contains:

- `/sbin/mke2fs`
- `/sbin/mkfs.ext2`
- `/sbin/e2fsck`
- `/sbin/fsck.ext2`

The preserved merged root filesystem had the following properties:

- SHA-256: `989e7cfbf39734623a77ed35f563c9c7db566815cddb48e20e1093a9b229487d`
- Size: `19144704` bytes
- Firmware UUID: `edd3b032-09f5-597f-0e92-ce1339c9a8a0`

The firmware was written using the existing one-partition Flat SD layout and
booted successfully on the physical Atom Cam 2.

Target verification confirmed:

- `mke2fs`, `mkfs.ext2`, `e2fsck`, and `fsck.ext2` resolve from `/sbin`
- all four commands execute successfully
- the installed e2fsprogs version is `1.47.4`
- `/proc/filesystems` reports ext2 support
- the running control kernel SHA-256 remains
  `b50658eac32b57fdcb20383d82a54e6439acd7a3f7e9cb8b43edf4a4b89b03bc`

No filesystem was created and no block device was modified during this
verification.

This confirms that the protected kernel and userspace can create and repair an
ext2 filesystem. Partition creation, mounting, persistence, repair behavior, and
power-interruption testing remain separate milestones.

## Stable root-disk alias verification

### Implementation boundary

The standard Nerves-style root-disk aliases must not be implemented by changing the custom initramfs. The generated kernel is replaced during packaging by the protected Atom Cam 2 control kernel, whose SHA-256 is verified before use.

The aliases are therefore established from the writable root filesystem by `/usr/bin/atomcam2-pre-run` before Erlang starts.

The implementation:

- identifies the mounted boot partition from `/proc/mounts`
- derives the parent MMC block device
- creates `/dev/rootdisk0` for the whole SD card
- creates `/dev/rootdisk0p1` for the boot partition
- creates `/dev/rootdisk0p2` only when the second partition exists
- removes a stale `/dev/rootdisk0p2` alias when the second partition is absent
- enables the BusyBox `ln` and `rm` applets required by the pre-run script

The implementation was committed as:

```text
3bce8ed feat(system): establish stable root disk aliases
```

### Initial physical verification

The first firmware build booted successfully, and device discovery identified the expected paths:

```text
root_disk=/dev/mmcblk0
boot_partition=/dev/mmcblk0p1
data_partition=/dev/mmcblk0p2
```

However, the pre-run report recorded:

```text
rootdisk_links=0
```

All aliases were absent:

```text
/dev/rootdisk0=absent
/dev/rootdisk0p1=absent
/dev/rootdisk0p2=absent
```

The target did not contain an executable `ln` command:

```text
System.cmd("ln", ...) => :enoent
```

Although `/bin/busybox` existed, its `ln` applet was disabled:

```text
ln: applet not found
```

The BusyBox configuration was therefore updated to enable:

```text
CONFIG_LN=y
CONFIG_RM=y
```

### Successful physical verification

The rebuilt firmware UUID was:

```text
aca4fabc-c008-5727-b1f6-baff68bcd133
```

The required commands were present:

```text
ln=/bin/ln
rm=/bin/rm
```

The running one-partition card exposed the expected stable aliases:

```text
/dev/rootdisk0 -> /dev/mmcblk0
/dev/rootdisk0p1 -> /dev/mmcblk0p1
/dev/rootdisk0p2 absent
```

The pre-run report confirmed successful alias creation:

```text
stage=pre_run_complete
rootdisk_links=1
root_disk=/dev/mmcblk0
boot_partition=/dev/mmcblk0p1
data_partition=/dev/mmcblk0p2
hostname=nerves
wlan0_present=0
```

The protected control kernel remained unchanged:

```text
b50658eac32b57fdcb20383d82a54e6439acd7a3f7e9cb8b43edf4a4b89b03bc
```

No partition was created, resized, formatted, mounted, or otherwise modified during this milestone.

### Conclusion

The application now has stable paths for the physical SD card and its existing boot partition without modifying the protected kernel:

```text
/dev/rootdisk0
/dev/rootdisk0p1
```

The future data-partition alias is intentionally absent until `/dev/mmcblk0p2` exists:

```text
/dev/rootdisk0p2
```

This establishes the device-path prerequisite for implementing the ADR 0005 partition layout in `fwup.conf`. It does not yet verify partition creation, ext2 formatting, mounting at `/data`, upgrade preservation, or factory reset behavior.

## Host-side partition layout verification

### Implementation

The MicroSD layout now contains:

```text
partition 1: FAT boot and provisioning filesystem
partition 2: Linux application-data partition
```

The boot partition remains fixed at 512 MiB:

```text
BOOT_PART_OFFSET=2048
BOOT_PART_COUNT=1048576
```

The data partition begins immediately after it:

```text
DATA_PART_OFFSET=BOOT_PART_OFFSET+BOOT_PART_COUNT
DATA_PART_COUNT=1048576
```

Partition 2 uses MBR type `0x83` and expands to fill the remaining media.

The `complete` task invalidates the beginning of partition 2 rather than
formatting it:

```text
raw_memset(${DATA_PART_OFFSET}, 256, 0xff)
```

The `upgrade` task requires both expected partition offsets. It updates only
the protected kernel and root filesystem files on partition 1 and does not
write to partition 2.

The implementation was committed as:

```text
df62180 feat(system): add persistent data partition layout
```

### Firmware build verification

The firmware was rebuilt after verifying that `ATOMCAM2_KERNEL_IMAGE` pointed
to the protected Atom Cam 2 control kernel.

The packaged kernel SHA-256 remained:

```text
b50658eac32b57fdcb20383d82a54e6439acd7a3f7e9cb8b43edf4a4b89b03bc
```

The firmware archive was built successfully with fwup 1.16.0. This verified
that the partition-layout configuration parsed correctly and that all packaged
resources resolved.

The firmware-description wording was refined afterward. That metadata-only
change did not alter the verified partition layout or task behavior.

### Complete-task verification

The `complete` task was applied to a 2 GiB regular file. No physical block
device or MicroSD card was written during this test.

The resulting MBR was:

```text
partition 1:
  start=2048
  size=1048576
  type=c
  bootable=true

partition 2:
  start=1050624
  size=3143680
  type=83
```

This confirmed that:

- partition 1 remained exactly 512 MiB
- partition 2 began immediately after partition 1
- partition 2 expanded to occupy the remaining image
- partition 2 used the Linux MBR partition type

The first sector of partition 2 contained only `0xff` bytes.

Host-side filesystem probing found no filesystem signature on partition 2,
confirming that `complete` left it deterministically uninitialized for
target-side first-boot initialization.

### Upgrade preservation verification

A marker was written inside partition 2 before applying the `upgrade` task.

The SHA-256 of the first MiB of partition 2 before upgrade was:

```text
ab5df0f2d357f9458eee77fb40058e364cf9d12fef10fe0879f5b03653c1ae3f
```

The SHA-256 after upgrade was identical:

```text
ab5df0f2d357f9458eee77fb40058e364cf9d12fef10fe0879f5b03653c1ae3f
```

The partition table was unchanged, and the explicit marker survived byte for
byte.

This confirms at the host-image level that the `upgrade` task preserves the
data partition.

### Legacy-layout rejection verification

A separate 2 GiB image was changed to contain only the former one-partition
layout:

```text
partition 1:
  start=2048
  size=1048576
  type=c
```

The `upgrade` task rejected this image because the required partition 2 offset
was absent:

```text
fwup: Couldn't find applicable task 'upgrade'. If task is available, the task's requirements may not be met.
```

This confirms that firmware expecting the persistent data partition cannot be
applied through `upgrade` to legacy flat-SD media.

### Conclusion

The host-side partition lifecycle now satisfies these ADR 0005 requirements:

- `complete` creates a separate expanding Linux data partition
- `complete` leaves the data partition uninitialized
- `upgrade` requires the new two-partition layout
- `upgrade` rejects legacy one-partition media
- `upgrade` preserves the data partition
- the protected control kernel remains unchanged

This does not yet verify:

- first-boot ext2 formatting
- mounting partition 2 at `/data`
- Nerves Runtime metadata and initialization behavior
- persistence of NervesSSH and NervesTime state
- physical MicroSD boot behavior
- filesystem repair and reformat behavior
- power-interruption recovery
- factory reset

ADR 0005 therefore remains Proposed.

## Target-side data initialization artifact verification

### Implementation

Nerves Runtime now receives the standard application-partition metadata through
the existing in-memory firmware metadata backend:

```text
a.nerves_fw_application_part0_devpath=/dev/rootdisk0p2
a.nerves_fw_application_part0_fstype=ext2
a.nerves_fw_application_part0_target=/data
```

This configuration directs Nerves Runtime to:

1. mount partition 2 read-write at `/data`
2. format it as ext2 when it cannot be mounted
3. retry the mount after formatting

The implementation was committed as:

```text
f9a574c feat(system): configure persistent data partition
```

### Mount-point correction

The inherited Nerves root filesystem contained:

```text
/data -> root/
```

Running `mkdir -p` against this path preserved the symlink rather than creating
a dedicated mount-point directory.

The Atom Cam 2 post-build step now removes the inherited `/data` symlink and
creates `/data` as a real directory. It also rejects unexpected non-directory
entries instead of silently replacing them.

### Firmware build verification

A fresh firmware build completed successfully after verifying the protected
Atom Cam 2 control kernel.

The protected kernel SHA-256 remained:

```text
b50658eac32b57fdcb20383d82a54e6439acd7a3f7e9cb8b43edf4a4b89b03bc
```

The build log was:

```text
tmp/log/mix-firmware-20260719-214357.log
```

The resulting firmware metadata included:

```text
description: Atom Cam 2 Nerves firmware
UUID: 70a3128f-f61b-59ba-9711-8d3fe7138479
nickname: hello-online
```

The generated release configuration contained all three application-partition
metadata keys.

### Final root filesystem verification

The Buildroot target contained `/data` as a real directory:

```text
drwxr-xr-x ... target/data/
```

The final combined squashfs also contained `/data` as a directory:

```text
drwxr-xr-x root/root ... squashfs-root/data
```

The required ext2 commands were present:

```text
/sbin/mke2fs
/sbin/mkfs.ext2 -> mke2fs
/sbin/e2fsck
/sbin/fsck.ext2 -> e2fsck
```

This confirms that the final firmware contains:

- a valid `/data` mount point
- the Nerves Runtime application-partition metadata
- the command used to create an ext2 filesystem
- the command used to inspect and repair an ext2 filesystem

### Conclusion

The firmware artifact now contains the complete target-side mechanism required
for first-boot initialization of partition 2.

This does not yet prove that physical hardware will:

- expose `/dev/mmcblk0p2` and `/dev/rootdisk0p2` at the required time
- format partition 2 successfully
- mount partition 2 read-write at `/data`
- preserve files across reboot
- recover from filesystem errors
- behave safely during power interruption
- reset only `/data` during a complete rewrite

No physical MicroSD card was written during this verification.

ADR 0005 therefore remains Proposed.

## Physical first-boot data partition verification

### Complete installation

The freshly built firmware was written to a removable 14.6 GiB MicroSD card
using the fwup `complete` task.

fwup completed successfully:

    100% [====================================] 20.98 MB in / 21.25 MB out
    Success!

The resulting physical partition table was:

    /dev/sda1: start=2048, size=1048576, type=c, bootable
    /dev/sda2: start=1050624, size=29485056, type=83

Partition 1 was 512 MiB, and partition 2 expanded across the remaining card.

### Pre-boot data partition state

Before inserting the card into the camera:

- `wipefs --no-act` found no signature on partition 2
- a cache-free `blkid` probe reported no filesystem type, UUID, or label
- the first 128 KiB of partition 2 contained only `0xff`

The measured SHA-256 for that 128 KiB region was:

    b5a41c3758763bbec72769fab4a2533bf2db0b6312d93d25a695f9e4b9e02260

The protected kernel copied to the physical card retained the required
SHA-256:

    b50658eac32b57fdcb20383d82a54e6439acd7a3f7e9cb8b43edf4a4b89b03bc

### First boot

The camera booted successfully from the new two-partition layout.

The stable device alias was present:

    /dev/rootdisk0p2 -> /dev/mmcblk0p2

Nerves Runtime formatted and mounted partition 2:

    /dev/rootdisk0p2 /data ext2 rw,relatime,errors=continue 0 0

`/data` was a read-write directory, and `df` reported approximately 13.8 GiB
of total capacity.

This proves that the target-side initialization path successfully:

- detected the uninitialized partition
- created an ext2 filesystem
- mounted it read-write at `/data`

### Graceful reboot persistence

A marker was written to:

    /data/adr0005-persistence.txt

The file contents were:

    ADR 0005 persistence verification

The target did not contain a standalone `sync` command, so the marker file
was synchronized using `:file.sync/1`. The operation returned `{:ok, :ok}`.

The device was then rebooted with `Nerves.Runtime.reboot/0`.

After reboot:

- `/data` was mounted read-write as ext2
- `/dev/rootdisk0p2` still resolved to `/dev/mmcblk0p2`
- the marker contents were preserved
- `/proc/uptime` reported approximately 106 seconds

This verifies persistent application data across a graceful reboot.

### Remaining physical verification

The following behavior remains unverified:

- moving NervesSSH and NervesTime state from the FAT partition to `/data`
- physical `upgrade` preservation of `/data`
- filesystem checking and repair behavior
- controlled reformat behavior for an unusable filesystem
- recovery after power interruption
- factory reset behavior

ADR 0005 therefore remains Proposed.

## Physical upgrade and runtime-state persistence verification

### Pre-upgrade state

Before applying the new firmware, partition 2 was mounted as:

    /dev/rootdisk0p2 /data ext2 rw,relatime,errors=continue 0 0

The existing persistence marker had SHA-256:

    7af01eb9853e9d6e88f953aea06188a6367c1435f2ae7cc59e6f6336283bc914

The running firmware still used the former FAT-backed paths:

    /media/mmc/.nerves_time
    /media/mmc/nerves_ssh
    /media/mmc/nerves_ssh/default_user

The corresponding `/data` paths did not yet exist.

### Physical upgrade

The firmware built from commit `85c8b0e` was applied to the physical
MicroSD card with the fwup `upgrade` task.

The firmware metadata was:

    UUID: a1e5b5d2-0344-51b1-1e97-3251ae94f1fa
    nickname: plug-thunder

fwup completed successfully:

    100% [====================================] 20.98 MB in / 21.12 MB out
    Success!

The partition table was unchanged.

The ext2 filesystem UUID remained:

    3041e38d-615b-48d4-affb-a7787b5c4c39

The persistence-marker SHA-256 was unchanged after the host-side upgrade.

This verifies that the physical `upgrade` task preserved partition 2.

### Runtime-state migration

After booting the upgraded firmware, the running applications used:

    NervesTime: /data/.nerves_time
    NervesSSH system directory: /data/nerves_ssh
    NervesSSH user directory: /data/nerves_ssh/default_user

The original persistence marker remained readable with the expected hash.

NervesTime created `/data/.nerves_time`.

NervesSSH created persistent files including:

    /data/nerves_ssh/default_user/authorized_keys
    /data/nerves_ssh/ssh_host_ed25519_key

The initial hashes were:

    authorized_keys:
    eac4efac1f7c5349313917ada322f5586e45a4ecb0da2b91e697add47f04b8ed

    ssh_host_ed25519_key:
    e0480b5ed447ca715aa1b3469e8db39d995c718f7702faf0fbf32fa28df79bc8

The former FAT-backed files remained on partition 1 because the upgrade task
preserves unrelated boot-partition files. The running applications no longer
used those paths.

### Graceful reboot persistence

The upgraded device was rebooted gracefully.

After reboot:

- `/data` was mounted read-write as ext2
- the original application marker remained unchanged
- NervesTime still used `/data/.nerves_time`
- NervesSSH still used `/data/nerves_ssh`
- the authorized-keys hash was unchanged
- the SSH host-key hash was unchanged
- SSH remained accessible

This verifies that both application data and framework-generated persistent
state survive a physical firmware upgrade and subsequent graceful reboot.

### Remaining physical verification

The following behavior remains unverified:

- filesystem checking and repair behavior
- controlled reformat behavior for an unusable filesystem
- recovery after power interruption
- factory reset behavior

ADR 0005 therefore remains Proposed.

## Filesystem recovery-policy audit

### Standard Nerves Runtime behavior

The example application locks:

    nerves_runtime 0.13.13

Inspection of `Nerves.Runtime.Init` confirmed this sequence:

1. Inspect the current application-partition mount state.
2. Unmount `/data` if it is mounted read-only.
3. Attempt to mount the application partition read-write.
4. If it remains unmounted, run `mkfs.ext2`.
5. Attempt the read-write mount again.

For the Atom Cam 2 metadata, the formatting command is equivalent to:

    mkfs.ext2 -U 3041e38d-615b-48d4-affb-a7787b5c4c39 \
      -F /dev/rootdisk0p2

The initializer does not run `e2fsck` or `fsck.ext2` before formatting.
Non-zero command results are logged but otherwise ignored.

Consequently, the standard initializer cannot distinguish:

- a deliberately invalidated first-boot partition
- a recoverable ext2 mount failure
- an unrecoverable filesystem failure
- a missing or temporarily unavailable block device

Using it unchanged could erase recoverable application data after any mount
failure.

### Custom initializer boundary

Nerves Runtime supports replacing its initializer through:

    config :nerves_runtime, init_module: MyApp.FilesystemInit

The configured module is started as a supervised child. A one-shot `GenServer`
that performs initialization and returns `:ignore` matches the standard module
boundary.

`Nerves.Runtime.cmd/3` may be reused to execute target commands. It returns
status `255` when an executable is unavailable rather than raising.

### Target tooling

The physical target provided:

    /bin/mount
    /bin/umount
    /sbin/e2fsck
    /sbin/fsck.ext2
    /sbin/mke2fs
    /sbin/mkfs.ext2
    /sbin/dumpe2fs

`blkid` was not present and is not required by the proposed initializer.

The installed e2fsprogs version was:

    e2fsck 1.47.4
    mke2fs 1.47.4

### Invalidation-marker detection

The first 128 KiB of `/dev/rootdisk0p2` was read directly from Elixir.

The formatted physical filesystem produced:

    initialization_region_size: 131072
    initialization_region_state: existing_filesystem

This confirms that the initializer can recognize the all-`0xff` state created
by the fwup `complete` task without requiring another userspace command.

Only an exact all-`0xff` region may authorize formatting. Read failures, short
reads, and all other content must be treated as an existing or unknown
filesystem state.

### Recovery-policy conclusion

The Atom Cam 2 application must override the standard Nerves Runtime
initializer.

The custom policy will:

- format only an explicitly invalidated partition
- attempt `e2fsck -p -f` after an existing filesystem fails to mount
- retry mounting only after status `0` or `1`
- leave `/data` unmounted when the status contains the reboot-required value
  `2`, or after any failure status
- never format an existing or unknown filesystem automatically

No filesystem corruption test should be performed until this safer initializer
has been implemented and verified.

ADR 0005 remains Proposed.

## Safe filesystem initializer implementation

Commit `244ef5e` introduced the Atom Cam 2-specific application-data
filesystem initializer.

### Implementation boundary

The implementation adds:

- `Atomcam2NervesApp.FilesystemInit`
- an explicit `:nerves_runtime, :init_module` override
- focused host-side tests for marker and repair-status policy

The initializer remains a one-shot `GenServer` and returns `:ignore` after
initialization, matching the standard Nerves Runtime initialization boundary.

It continues using the existing Nerves Runtime application-partition metadata:

    devpath: /dev/rootdisk0p2
    fstype: ext2
    target: /data

### Destructive-operation boundary

Automatic formatting is permitted only when the first 128 KiB of the data
partition is exactly filled with `0xff`.

The following states do not authorize formatting:

- existing filesystem content
- non-marker content
- short reads
- read failures
- mount failures
- filesystem-check failures
- missing executables

For an existing or unknown filesystem, the initializer:

1. Attempts a read-write mount.
2. Ensures the filesystem is unmounted after mount failure.
3. Runs `e2fsck -p -f`.
4. Retries the mount only after status `0` or `1`.
5. Otherwise leaves `/data` unmounted without formatting.

Filesystem-check statuses `2` and `3` are reported as requiring a reboot.
Failure statuses take precedence over the reboot-required bit, so combined
failure statuses such as `6` remain ordinary failures.

### Host verification

The focused host test command was:

    MIX_TARGET=host mix test --no-start test/filesystem_init_test.exs

Result:

    6 tests, 0 failures

The tests confirmed:

- only an exact all-`0xff` region selects formatting
- existing, unknown, and read-error states select mount or repair
- statuses `0` and `1` permit a mount retry
- statuses `2` and `3` report that a reboot is required
- statuses `4`, `6`, `8`, and `255` leave `/data` unmounted
- unexpected status values leave `/data` unmounted

The repository smoke check also completed successfully.

### Locked dependency API verification

The implementation was checked against `nerves_runtime` 0.13.13.

The following invoked APIs exist with the required argument order:

- `Nerves.Runtime.KV.get_active/1`
- `Nerves.Runtime.MountInfo.get_mounts!/0`
- `Nerves.Runtime.MountInfo.find_by_mount_point/2`
- `Nerves.Runtime.MountInfo.read_only?/1`
- `Nerves.Runtime.cmd/3`

`Nerves.Runtime.cmd/3` accepts `:return` and returns `{output, status}`.
When an executable is unavailable, it returns status `255` rather than
raising. The custom initializer treats that result as a failure and never
formats the data partition.

### Target build verification

A fresh target firmware was built with the verified protected control kernel.

Firmware metadata:

    UUID: 6b3b37d0-0484-515a-aac2-2294825a4e93
    nickname: grunt-crucial
    size: 20981813 bytes
    creation time: 2026-07-20 10:56 JST

The packaged protected kernel SHA-256 remained:

    b50658eac32b57fdcb20383d82a54e6439acd7a3f7e9cb8b43edf4a4b89b03bc

The final root filesystem contained:

- `Elixir.Atomcam2NervesApp.FilesystemInit.beam`
- the `init_module` override in `sys.config`
- the expected `/dev/rootdisk0p2`, ext2, and `/data` metadata

### Physical verification status

Physical verification followed this implementation review. The results are
recorded in the physical custom initializer verification section below.

ADR 0005 remains Proposed pending controlled verification of the destructive
formatting and filesystem-recovery paths.

## Physical custom initializer verification

The custom filesystem initializer was verified on the physical Atom Cam 2
using firmware UUID `6b3b37d0-0484-515a-aac2-2294825a4e93`.

### Pre-upgrade filesystem state

Before the upgrade, the existing ext2 data filesystem had:

    UUID: 3041e38d-615b-48d4-affb-a7787b5c4c39
    first MiB SHA-256: 727243d2f84c4836a36ced20f96d20c4a53997932f5fe5ffb2a259b36f0f2a73

The ext2 superblock was marked `not clean`, but a non-modifying
`e2fsck -f -n` completed with status `0` and found no structural errors.

### Offline upgrade verification

The `fwup` `upgrade` task completed successfully.

The following remained unchanged after the upgrade:

- partition table
- ext2 filesystem UUID
- first MiB of the data partition
- protected control-kernel SHA-256
- persistence marker
- NervesSSH host key
- authorized keys
- NervesTime state file

The protected control-kernel SHA-256 remained:

    b50658eac32b57fdcb20383d82a54e6439acd7a3f7e9cb8b43edf4a4b89b03bc

### First boot with the custom initializer

The installed release reported:

    init_module: Atomcam2NervesApp.FilesystemInit
    rootdisk0p2: /dev/mmcblk0p2
    mount source: /dev/rootdisk0p2
    mount point: /data
    filesystem: ext2
    mount mode: read-write

The initializer module was loaded from the installed release. Its registered
process was absent after initialization, as expected for the one-shot
`GenServer` that returns `:ignore`.

The existing filesystem mounted successfully without formatting or repair.

Persistent-state hashes remained:

    marker: 7af01eb9853e9d6e88f953aea06188a6367c1435f2ae7cc59e6f6336283bc914
    SSH host key: e0480b5ed447ca715aa1b3469e8db39d995c718f7702faf0fbf32fa28df79bc8
    authorized keys: eac4efac1f7c5349313917ada322f5586e45a4ecb0da2b91e697add47f04b8ed

The NervesTime state file continued to exist.

### Normal reboot verification

After a graceful reboot, the custom initializer again completed successfully.

`/data` was mounted as ext2 read-write from `/dev/rootdisk0p2`, and the
persistence marker, SSH host key, authorized keys, and NervesTime state
remained present.

The firmware banner continued to report `UUID unavailable` because this Flat
SD configuration uses an in-memory Nerves Runtime KV backend without the
firmware UUID entry. Firmware identity was therefore verified from the host
firmware archive and installed initializer rather than the runtime banner.

### Verified behavior

The physical tests now confirm:

- non-destructive firmware upgrade preserves the data partition
- the custom initializer mounts a healthy existing ext2 filesystem
- normal reboot preserves the mounted data filesystem and persistent state
- the protected control kernel remains unchanged

### Remaining verification

The following behavior remains unverified:

- explicit invalidation-marker formatting
- mount-failure filesystem checking and repair
- reboot-required filesystem-check status handling
- recovery after power interruption
- factory reset behavior

Intentional corruption remains deferred until a controlled recovery-test
procedure has been defined. A byte-for-byte restorable MicroSD backup is
recorded below.

ADR 0005 remains Proposed.

## Recovery-test backup verification

Before beginning controlled formatting or recovery-path tests, a complete
image of the physical MicroSD card was created outside the repository.

Backup image:

    ~/Backups/atomcam2/20260720-before-filesystem-recovery-tests.img

Backup SHA-256:

    cef7d56975b019fb9951c1c73851d34c328ab5e4e1c2da71e2528bb7630a57eb

### Backup verification

The backup was verified through all of the following checks:

- the stored SHA-256 checksum passed
- the image size exactly matched the physical MicroSD device
- the image partition table matched the physical card
- the ext2 filesystem UUID matched
- the protected control-kernel SHA-256 matched
- the persistence marker matched
- the NervesSSH host key matched
- the authorized keys matched
- the NervesTime state file matched
- a full-device `cmp` confirmed byte-for-byte equality

The verified data-partition first-MiB SHA-256 at backup time was:

    ce70c2b6e1a08c5f129494984d83883652c58c7220d9412aa93119258ce748f8

This differs from the earlier pre-boot value because normal ext2 mounts
updated mutable superblock metadata after the firmware-upgrade comparison.
The earlier value remains valid evidence that the `fwup` `upgrade` task
itself did not modify the data partition.

The backup image was attached through a read-only loop device for inspection
and detached after verification.

This image provides a byte-for-byte restoration point for the upcoming
controlled filesystem initialization and recovery tests.

ADR 0005 remains Proposed.

## Controlled invalidation-marker test plan

The next physical test will verify the custom initializer's explicit
invalidation-marker formatting path.

This is not a general corruption-recovery test. The test will deliberately
replace only the first 128 KiB of the ext2 data partition with the exact
all-`0xff` marker produced by the fwup `complete` task.

### Purpose

The test must confirm that:

- only the exact invalidation marker authorizes formatting
- the custom initializer creates a new ext2 filesystem
- the fixed data-filesystem UUID is restored
- `/data` mounts read-write after formatting
- data from the previous filesystem is no longer present
- runtime services can recreate their required state
- the partition table and protected control kernel remain unchanged

### Safety prerequisites

The test may proceed only while all of the following remain true:

- the camera is powered off
- the selected device is the removable Atom Cam 2 MicroSD card
- both MicroSD partitions are unmounted
- the verified full-device backup remains available
- the backup SHA-256 remains verified
- the physical card still matches the backup before the destructive write

Verified restoration image:

    ~/Backups/atomcam2/20260720-before-filesystem-recovery-tests.img

Verified image SHA-256:

    cef7d56975b019fb9951c1c73851d34c328ab5e4e1c2da71e2528bb7630a57eb

### Exact marker

The marker must be exactly 131072 bytes of `0xff`.

Its expected SHA-256 is:

    b5a41c3758763bbec72769fab4a2533bf2db0b6312d93d25a695f9e4b9e02260

A short write, a different byte value, or a write to any other offset is not
part of this test and must cause the procedure to stop.

### Planned procedure

1. Revalidate the removable whole-disk path and unmounted state.
2. Reverify the backup checksum.
3. Capture the current partition table, protected-kernel hash, ext2 metadata,
   and persistent-file hashes.
4. Create a local 128 KiB all-`0xff` marker file and verify its size and hash.
5. Write that marker only to offset zero of partition 2.
6. Read back the first 128 KiB and verify the exact marker hash.
7. Confirm that the partition table and partition 1 remain unchanged.
8. Eject the MicroSD card and boot the camera.
9. Verify that the custom initializer formats and mounts `/data` read-write.
10. Verify that the previous persistence marker is absent.
11. Verify that the SSH host key is newly generated rather than preserved.
12. Verify that normal reboot continues to mount the new filesystem.

The fixed filesystem UUID may remain
`3041e38d-615b-48d4-affb-a7787b5c4c39` after formatting. Therefore, a
matching UUID alone is not evidence that formatting occurred. Filesystem
creation metadata and removal of previous application data must also be
verified.

### Stop conditions

The procedure must stop before boot when:

- the selected device is not `/dev/sda` or is not removable
- either partition is mounted
- the backup checksum fails
- the physical card no longer matches the verified backup unexpectedly
- the marker size or SHA-256 is incorrect
- the marker read-back verification fails
- the partition table changes
- the protected control-kernel hash changes

If the camera fails to boot or `/data` remains unavailable, no manual
formatting should be attempted. The card should be powered down and restored
from the verified full-device image.

### Out of scope

This test does not cover:

- arbitrary ext2 corruption
- automatic `e2fsck` repair
- reboot-required filesystem-check statuses
- uncorrectable filesystem-check statuses
- power-interruption recovery
- product-level factory-reset behavior

ADR 0005 remains Proposed until the planned physical evidence has been
captured.

## Physical invalidation-marker formatting verification

The explicit invalidation-marker formatting path was tested on the physical
Atom Cam 2 MicroSD card.

The test began from the verified byte-for-byte recovery image recorded
above. Only the first 128 KiB of partition 2 was replaced with the exact
all-`0xff` marker produced by the fwup `complete` task.

Marker size:

    131072 bytes

Marker SHA-256:

    b5a41c3758763bbec72769fab4a2533bf2db0b6312d93d25a695f9e4b9e02260

Before boot, the marker was verified both by SHA-256 and byte-for-byte
comparison. The partition table and protected control kernel remained
unchanged.

### Initial failed formatting attempt

The first boot did not format or mount `/data`.

Observed state:

- `/data` was not mounted
- `dumpe2fs` reported no valid filesystem superblock
- the exact all-`0xff` marker remained present
- application-partition metadata was correct
- `mkfs.ext2`, `e2fsck`, `mount`, `umount`, and `dumpe2fs` were available

The failure was traced to the return shape of `File.open/3`. With a callback,
`File.open/3` returned `{:ok, region}`, but the initializer passed that
entire tuple to `classify_initialization_region/1`.

The tuple was therefore classified as `:unknown`, causing the safe
`:mount_or_repair` path rather than the authorized `:format` path.

This failure confirmed an important safety property: an unrecognized marker
read result did not authorize formatting.

The device was powered off without modifying partition 2.

### Corrective change

Commit `8e18c27` corrected the initializer by explicitly unwrapping successful
`File.open/3` callback results before classifying the region.

A regression test using the real `File.open/3` callback return shape was
added. The focused host test suite completed with:

    7 tests, 0 failures

The repository smoke check also passed.

Corrected firmware:

    UUID: 34c5052c-caf3-5765-4090-153412ba5a9c
    nickname: cloud-snack

The corrected classifier was verified in both the built firmware artifact
and the root filesystem installed on the MicroSD card.

The non-destructive fwup `upgrade` task preserved all of the following:

- the partition table
- the exact 128 KiB invalidation marker
- the first MiB of partition 2
- the protected control kernel

The protected control-kernel SHA-256 remained:

    b50658eac32b57fdcb20383d82a54e6439acd7a3f7e9cb8b43edf4a4b89b03bc

### Successful formatting boot

On the next boot, the corrected initializer recognized the exact marker and
created a new ext2 filesystem.

Observed mount state:

    source: /dev/rootdisk0p2
    resolved device: /dev/mmcblk0p2
    mount point: /data
    filesystem: ext2
    mode: read-write

The new filesystem UUID was:

    3041e38d-615b-48d4-affb-a7787b5c4c39

`dumpe2fs` completed with status `0`. The first 128 KiB was no longer the
invalidation marker and was classified as an existing filesystem.

First-128-KiB SHA-256 after formatting:

    138695a939d0d73bd64cbe16ef15e3adcad28abcd1bbfb8b4890713628f60256

The previous persistence marker was absent, confirming that the old
filesystem contents had not been preserved.

Runtime services recreated their required state:

- NervesSSH generated a new host key
- the configured authorized keys were restored
- NervesTime recreated `/data/.nerves_time`

New SSH host-key SHA-256:

    c8282dbd553115112f4af0a8a477b3fca8124b7d2fe3e99fc91ec97667a1b19e

Authorized-keys SHA-256:

    eac4efac1f7c5349313917ada322f5586e45a4ecb0da2b91e697add47f04b8ed

### Post-format reboot verification

A new persistence marker was written to the formatted filesystem:

    /data/adr0005-format-reboot.txt

Marker SHA-256:

    115b27fc20c9da455798d34e91d5c4f32becc3115d30b64d1ae827e0e0a12ff6

The target did not expose a usable `sync` executable through
`Nerves.Runtime.cmd/3`; the attempted command returned status `255`.
A normal graceful reboot was used as the persistence boundary.

After reboot:

- `/data` mounted ext2 read-write
- the persistence marker remained unchanged
- the newly generated SSH host key remained unchanged
- the authorized keys remained unchanged
- the NervesTime state file remained present
- `dumpe2fs` completed with status `0`
- the filesystem mount count increased from `1` to `2`

The one-shot initializer process was absent after both successful boots, as
expected.

### Verified behavior

The physical tests now confirm:

- only the exact invalidation marker authorizes formatting
- the invalidated partition is formatted as ext2
- the fixed filesystem UUID is restored
- the formatted filesystem mounts read-write at `/data`
- previous application data is removed
- runtime services recreate their required persistent state
- the new filesystem survives a normal reboot
- fwup `upgrade` preserves an invalidation marker until the next boot
- the partition table and protected control kernel remain unchanged
- an unrecognized marker-read result fails safely without formatting

### Remaining verification

The following behavior remains unverified:

- mount-failure filesystem checking and repair
- reboot-required filesystem-check status handling
- uncorrectable filesystem-check status handling
- recovery after power interruption
- product-level factory-reset behavior

ADR 0005 remains Proposed.

## Controlled filesystem-repair test plan

The next physical milestone will verify the initializer's
mount-failure filesystem-check and repair path.

No further corruption will be applied directly to the physical MicroSD card
until a suitable fault has first been validated on a disposable ext2 image.

### Purpose

The test must confirm the following sequence:

1. the initialization region is classified as an existing filesystem
2. the initial read-write mount fails
3. the initializer ensures that the filesystem is unmounted
4. `e2fsck -p -f` runs against partition 2
5. `e2fsck` returns status `1`, indicating successful correction
6. the initializer retries the read-write mount
7. `/data` mounts successfully
8. existing application data remains intact

Status `0` would prove only that no correction was required. The preferred
test fault must therefore produce status `1` while remaining safely
repairable without manual input.

### Candidate-fault requirements

A candidate fault is acceptable only when all of the following are
demonstrated on a disposable image:

- the first 128 KiB is not the exact all-`0xff` invalidation marker
- the Linux ext2 driver refuses the initial read-write mount
- `e2fsck -p -f` performs an automatic repair
- the exact `e2fsck` exit status is `1`
- a second read-write mount succeeds
- test-file contents remain unchanged
- the filesystem UUID remains unchanged

The candidate must not:

- require interactive `e2fsck` confirmation
- require `e2fsck -y`
- require an alternate-superblock argument
- destroy directory contents
- alter partition 1
- resemble the explicit invalidation marker
- depend on undefined or version-specific behavior that cannot be reproduced

### Disposable-image qualification

Before touching the physical card, the candidate fault will be tested using
a host-side ext2 image attached through a loop device.

The qualification procedure will:

1. create a clean ext2 image using the same 4096-byte block size
2. create known files and record their SHA-256 hashes
3. record the filesystem UUID and clean baseline
4. duplicate the image before each candidate experiment
5. apply one narrowly defined fault to the duplicate
6. confirm that a read-write mount fails
7. run `e2fsck -p -f` and capture its exact output and status
8. confirm that status `1` is returned
9. mount the repaired image read-write
10. verify the UUID and all file hashes

Any candidate producing status `2`, `3`, `4`, `8`, `16`, `32`, `128`, a
combined failure status, or wrapper status `255` will be rejected for this
test.

### Physical-card prerequisites

After a candidate has passed disposable-image qualification, the physical
test may proceed only when:

- the camera has been shut down gracefully
- the selected device is the removable Atom Cam 2 MicroSD card
- both partitions are unmounted
- the verified full-device recovery image remains available
- the protected control-kernel hash is verified
- the partition table is recorded
- the filesystem UUID is recorded
- the format-reboot marker and persistent-state hashes are recorded

Current formatted-filesystem evidence includes:

    filesystem UUID:
    3041e38d-615b-48d4-affb-a7787b5c4c39

    format-reboot marker SHA-256:
    115b27fc20c9da455798d34e91d5c4f32becc3115d30b64d1ae827e0e0a12ff6

    SSH host-key SHA-256:
    c8282dbd553115112f4af0a8a477b3fca8124b7d2fe3e99fc91ec97667a1b19e

    authorized-keys SHA-256:
    eac4efac1f7c5349313917ada322f5586e45a4ecb0da2b91e697add47f04b8ed

### Physical verification

The qualified fault will be applied only to partition 2.

After boot, the test must capture:

- `/data` mounted from `/dev/rootdisk0p2`
- filesystem type `ext2`
- read-write mount mode
- unchanged filesystem UUID
- unchanged format-reboot marker hash
- unchanged SSH host-key hash
- unchanged authorized-keys hash
- `dumpe2fs` status and relevant metadata
- initializer log messages showing mount failure, filesystem check, and
  successful mount retry

A subsequent graceful reboot must again mount the repaired filesystem
without another repair or format operation.

### Stop conditions

The physical procedure must stop when:

- the candidate did not pass disposable-image qualification
- the selected device or partition is ambiguous
- either partition is mounted
- the recovery image cannot be verified
- the protected kernel or partition table differs unexpectedly
- the applied bytes differ from the qualified candidate fault

If the target remains unmounted after the filesystem check, no manual repair
or formatting will be performed on the target. The card will be powered
down for offline inspection or restoration.

### Out of scope

This test does not cover:

- reboot-required filesystem-check status `2`
- combined reboot-required status `3`
- uncorrectable status handling
- arbitrary primary-superblock destruction
- alternate-superblock recovery
- power-interruption recovery
- product-level factory-reset behavior

ADR 0005 remains Proposed.

## Disposable filesystem-repair fault qualification

A repairable ext2 fault was qualified entirely on disposable host-side
filesystem images before modifying the physical Atom Cam 2 MicroSD card.

The qualification used:

    filesystem: ext2
    block size: 4096 bytes
    inode size: 256 bytes
    image size: 256 MiB
    host e2fsprogs: 1.47.2

The physical target currently contains e2fsprogs 1.47.4. The disposable
test therefore qualifies the fault structure and expected behavior, while
the target-specific result must still be captured during the physical test.

### Clean baseline

A clean ext2 image was created and populated with two known files.

Baseline filesystem UUID:

    afce0d09-1f6e-4a5e-ad26-87969ea1286d

Qualification-marker SHA-256:

    0b863542aa8bd7c10d6db2cef0b5af7d9375d6bb879296b65acab8d546c11517

Application-state SHA-256:

    63dd2dbac1f902a45823bab6d6425fc6976031e7a415ec7f6b2f2cf4fa88bc1a

A forced read-only `e2fsck` completed with status `0`, confirming a clean
baseline.

### Rejected candidate A

Candidate A changed the primary superblock `s_first_data_block` field from
`0` to `1`.

The candidate remained distinct from the all-`0xff` invalidation marker.
Its first-128-KiB SHA-256 was:

    7721f5c72ea02479c912a92efe3a2f98bfd76a4322a8dbcb0e233c16a6a00573

The initial read-write mount failed with host mount status `32` and:

    Structure needs cleaning

However, the exact repair command:

    e2fsck -p -f

returned status `8` and reported that the primary superblock could not be
used without alternate-superblock recovery.

Candidate A was rejected because it produced an operational error rather
than an unattended repair.

The loop device was detached without applying this fault to physical media.

### Qualified candidate B

Candidate B changed only root inode 2's `i_blocks` field from `8` to `0`.
The root directory size and block pointers were left unchanged.

For the disposable image, the calculated values were:

    inode table block: 19
    root inode offset: 78080
    root i_blocks offset: 78108

These offsets are specific to the disposable image. They must not be reused
for the physical filesystem. The physical inode-table location and root
inode offset must be derived independently from its own metadata.

Candidate B remained distinct from the all-`0xff` invalidation marker.
Its first-128-KiB SHA-256 before repair was:

    803cf71cee3155020bd7e5be8a6c1a1d38f35b3a7bf3f7098c75931ff9ada0b5

### Candidate B qualification result

The initial read-write mount failed with:

    mount status: 32
    error: Structure needs cleaning

The exact initializer repair command was then run:

    e2fsck -p -f

It reported:

    Inode 2, i_blocks is 0, should be 8. FIXED.

The exact `e2fsck` status was:

    1

The repaired filesystem then mounted successfully as ext2 read-write.

Post-repair results:

    mount-after status: 0
    final e2fsck status: 0
    restored root i_blocks: 8

The filesystem UUID remained:

    afce0d09-1f6e-4a5e-ad26-87969ea1286d

The known file hashes remained unchanged:

    qualification marker:
    0b863542aa8bd7c10d6db2cef0b5af7d9375d6bb879296b65acab8d546c11517

    application state:
    63dd2dbac1f902a45823bab6d6425fc6976031e7a415ec7f6b2f2cf4fa88bc1a

A final forced read-only filesystem check returned status `0`.

The candidate loop device was detached after verification.

### Qualification conclusion

Candidate B satisfies the disposable-image requirements:

- the initialization region remains an existing-filesystem region
- the initial read-write mount fails
- `e2fsck -p -f` repairs the fault without interaction
- the exact repair status is `1`
- the repaired filesystem mounts read-write
- the filesystem UUID remains unchanged
- known file contents remain unchanged
- the repaired filesystem passes a final check with status `0`

Candidate B is therefore qualified for a controlled physical test.

Before applying it to the physical card, the procedure must independently
derive and verify:

- the physical filesystem block size
- the physical filesystem inode size
- the physical group-descriptor-table location
- the physical inode-table block
- the physical root inode offset
- the current physical root-inode `i_blocks` value
- the exact four original bytes that will be replaced

Only the four-byte root-inode `i_blocks` field may be modified.

ADR 0005 remains Proposed.

## Physical automatic filesystem repair verification

The qualified root-inode fault was applied to the physical MicroSD card
only after completing the disposable-image qualification and a read-only
physical pre-write gate.

### Recovery backup

A new full-device backup was created immediately before applying the
physical fault:

    /home/mnishiguchi/Backups/atomcam2/20260720-before-filesystem-repair-test.img

Its SHA-256 was:

    182f98fcf550a9fed0c2efa9050cfa57e16025ad78bf1983333682e7a19cf7e5

The backup size matched the 15,634,268,160-byte MicroSD device, its
checksum was verified, and a full-device `cmp` confirmed that it matched
the physical card byte-for-byte.

The earlier recovery image was also reverified successfully:

    cef7d56975b019fb9951c1c73851d34c328ab5e4e1c2da71e2528bb7630a57eb

### Physical pre-write gate

The physical partition layout remained:

    partition 1: start 2048, size 1048576, type 0x0c
    partition 2: start 1050624, size 29485056, type 0x83

Partition 2 was a clean ext2 filesystem before applying the fault:

    UUID: 3041e38d-615b-48d4-affb-a7787b5c4c39
    block size: 4096
    inode size: 256
    mount count: 2

The protected control kernel remained exactly:

    b50658eac32b57fdcb20383d82a54e6439acd7a3f7e9cb8b43edf4a4b89b03bc

The existing persistent files matched their previously captured hashes:

    format-reboot marker:
    115b27fc20c9da455798d34e91d5c4f32becc3115d30b64d1ae827e0e0a12ff6

    SSH host key:
    c8282dbd553115112f4af0a8a477b3fca8124b7d2fe3e99fc91ec97667a1b19e

    authorized keys:
    eac4efac1f7c5349313917ada322f5586e45a4ecb0da2b91e697add47f04b8ed

    NervesTime state:
    e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855

The physical root inode location was independently derived from the
filesystem metadata:

    inode table block: 903
    inode table offset: 3698688
    root inode offset: 3698944
    root i_blocks offset: 3698972
    whole-device i_blocks offset: 541618460
    root mode: 0x41ed
    root size: 4096
    root first direct block: 1413

The original root `i_blocks` bytes were:

    08 00 00 00

### Controlled physical fault

Only the four-byte root-inode `i_blocks` field was targeted. The value was
changed from `8` to `0`:

    before: 08 00 00 00
    after:  00 00 00 00

The guarded write:

- opened partition 2 rather than the whole device
- revalidated the block device and recorded filesystem geometry
- required the current bytes to match the captured original bytes
- wrote exactly four bytes
- flushed and synchronized the block-device file
- read the bytes back successfully
- verified that no surrounding inode bytes changed

The partition table, protected kernel, and first-128-KiB initialization
region remained unchanged after the write.

The initialization-region SHA-256 immediately before boot was:

    b3730d91f9cc2b7889da4a3dcc6d96e10aac6c64a6448a82e2330c5587ba8312

Both partitions were unmounted before returning the card to the camera.

### Target repair behavior

On the first boot after installing the fault, the kernel reported:

    EXT2-fs (mmcblk0p2): error: corrupt root inode, run e2fsck

This confirms that the initial read-write mount rejected the qualified
fault.

The custom initializer subsequently completed and exited:

    init module: Atomcam2NervesApp.FilesystemInit
    initializer process after boot: nil

The stable device alias remained:

    /dev/rootdisk0p2 -> /dev/mmcblk0p2

The repaired filesystem mounted successfully:

    mount point: /data
    filesystem type: ext2
    mount source: /dev/rootdisk0p2
    mount mode: read-write

The initialization region was classified as an existing filesystem and
selected the mount-or-repair path:

    initialization state: existing
    initialization action: mount_or_repair

A first target-side inode diagnostic calculated an invalid inode offset and
was discarded. A corrected diagnostic used an explicit inode-table offset
and verified the repaired root inode:

    inode table block: 903
    inode table offset: 3698688
    root inode offset: 3698944
    root i_blocks offset: 3698972
    root mode: 16877
    root size: 4096
    root i_blocks: 8
    root i_blocks bytes: 08000000
    root first direct block: 1413

This proves that the target restored the deliberately corrupted
`i_blocks` value from `0` to `8` before mounting `/data`.

### Persistent data preservation

The filesystem UUID remained:

    3041e38d-615b-48d4-affb-a7787b5c4c39

The following data remained present with unchanged hashes:

    format-reboot marker:
    115b27fc20c9da455798d34e91d5c4f32becc3115d30b64d1ae827e0e0a12ff6

    SSH host key:
    c8282dbd553115112f4af0a8a477b3fca8124b7d2fe3e99fc91ec97667a1b19e

    authorized keys:
    eac4efac1f7c5349313917ada322f5586e45a4ecb0da2b91e697add47f04b8ed

The NervesTime state file also remained present.

While `/data` was mounted read-write, `dumpe2fs` reported the filesystem
state as `not clean`. This is expected for an actively mounted ext2
filesystem and is not a repair failure.

### Verification conclusion

The physical test verifies the automatic-repair success path:

- the existing-filesystem region was not mistaken for an invalidation marker
- the initial read-write mount failed on the controlled corruption
- the target repaired the filesystem without interaction
- the root inode block count was restored from `0` to `8`
- the repaired filesystem mounted read-write
- the filesystem UUID remained unchanged
- application and SSH state remained unchanged
- the protected kernel and partition layout remained unchanged

A graceful reboot and final offline clean-filesystem check remain before
closing the physical repair verification.

ADR 0005 remains Proposed.

## Physical repair reboot and final offline verification

The repaired physical filesystem was subjected to one graceful reboot
followed by a graceful poweroff and a final offline read-only filesystem
check.

### Reboot verification

After the graceful reboot, `/data` mounted successfully:

    mount point: /data
    filesystem type: ext2
    mount source: /dev/rootdisk0p2
    mount mode: read-write

The custom initializer completed and exited:

    init module: Atomcam2NervesApp.FilesystemInit
    initializer process after boot: nil

The stable device alias remained:

    /dev/rootdisk0p2 -> /dev/mmcblk0p2

The repaired root inode remained valid:

    block size: 4096
    inode size: 256
    inode table block: 903
    inode table offset: 3698688
    root inode offset: 3698944
    root i_blocks offset: 3698972
    root mode: 16877
    root size: 4096
    root i_blocks: 8
    root i_blocks bytes: 08000000
    root first direct block: 1413

The filesystem UUID remained:

    3041e38d-615b-48d4-affb-a7787b5c4c39

The ext2 mount count increased from `1` on the repair boot to `2` after
the subsequent reboot.

No new corrupt-root-inode message appeared in the kernel log.

The persistent files remained unchanged:

    format-reboot marker:
    115b27fc20c9da455798d34e91d5c4f32becc3115d30b64d1ae827e0e0a12ff6

    SSH host key:
    c8282dbd553115112f4af0a8a477b3fca8124b7d2fe3e99fc91ec97667a1b19e

    authorized keys:
    eac4efac1f7c5349313917ada322f5586e45a4ecb0da2b91e697add47f04b8ed

The NervesTime state file also remained present.

While `/data` was mounted read-write, `dumpe2fs` reported `not clean`,
which is the expected state for an actively mounted ext2 filesystem.

### Graceful poweroff verification

The camera was then powered off through `Nerves.Runtime.poweroff/0`.

After removing the MicroSD card and connecting it to the host, both
partitions were unmounted before inspection.

The offline ext2 metadata showed:

    filesystem UUID: 3041e38d-615b-48d4-affb-a7787b5c4c39
    filesystem state: clean
    block size: 4096
    inode size: 256
    mount count: 2

This confirms that the graceful poweroff left the repaired filesystem in
a clean state.

### Final offline filesystem check

The host-side read-only command was run:

    e2fsck -f -n /dev/sda2

The host used e2fsprogs 1.47.2.

The check completed all five passes and returned:

    status: 0
    files: 17 of 922080
    blocks: 66877 of 3685632

No filesystem errors were reported.

A final direct read of the physical root inode confirmed:

    inode table block: 903
    inode table offset: 3698688
    root inode offset: 3698944
    root i_blocks offset: 3698972
    root mode: 16877
    root size: 4096
    root i_blocks: 8
    root i_blocks bytes: 08000000
    root first direct block: 1413

Partition 2 remained unmounted after the final verification.

### Final physical verification conclusion

The complete physical test verifies that the persistent-data design:

- recognizes the exact invalidation marker and formats only that state
- treats existing filesystem contents as data that must be preserved
- rejects a corrupt ext2 root inode on the initial mount attempt
- runs unattended filesystem repair on the target
- accepts repair status `1` and retries the mount
- restores the deliberately corrupted root inode metadata
- mounts the repaired filesystem read-write
- preserves the filesystem UUID and application data
- survives a subsequent graceful reboot
- reaches a clean state after graceful poweroff
- passes a final offline read-only filesystem check with status `0`

The protected control kernel, partition layout, stable device aliases, and
application-state paths remained intact throughout the test.

The physical verification required before accepting ADR 0005 is complete.

ADR 0005 remains Proposed in this commit so that its status transition can
be reviewed and committed separately.
