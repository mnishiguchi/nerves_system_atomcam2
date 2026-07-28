# ADR 0005: Provide a standard persistent data partition

## Status

Accepted

## Context

The Atom Cam 2 root filesystem is read-only, and the platform currently does not
provide the standard writable Nerves `/data` filesystem.

Runtime state is therefore stored directly on the writable MicroSD mount under
`/media/mmc`, including:

- The NervesTime timestamp file
- NervesSSH host keys and user state

This solved immediate persistence problems, but application-specific
`/media/mmc` paths are not the standard Nerves contract.

A standard Nerves system provides an application data filesystem mounted at
`/data`. It survives firmware upgrades, can be reset independently, and allows
libraries to use conventional persistent paths.

Firmware metadata is different from application data. It identifies the running
firmware and must change with firmware activation, so it must not become stale
state in `/data`.

The final Atom Cam 2 media uses an externally supplied control kernel whose
SHA-256 is protected by the build and release flow. The repository kernel
configuration currently disables ext2, ext3, ext4, and F2FS, but it does not by
itself prove which filesystems are available in the protected kernel binary.
Filesystem selection must therefore be based on read-only runtime inspection and
hardware evidence. This decision does not authorize replacing the protected
kernel or weakening its verification.

## Decision

Add a dedicated writable application-data partition to the Atom Cam 2 MicroSD
layout and mount it at `/data`.

The partition must:

- Be separate from the boot and provisioning filesystem.
- Use a Linux filesystem supported reliably by the protected kernel.
- Be initialized on first boot when necessary.
- Be mounted read-write before applications that depend on it start.
- Survive the fwup `upgrade` task.
- Be reset to an uninitialized, known state by the fwup `complete` task.
- Be clearable through a standard factory-reset operation.

A read-only hardware audit confirmed the following protected-kernel contract:

- The MicroSD device is `/dev/mmcblk0` on the verified hardware.
- The existing boot filesystem is `/dev/mmcblk0p1`.
- The protected kernel supports ext2, VFAT, exFAT, JFFS2, and SquashFS.
- The protected kernel does not report ext4 or F2FS support.
- The original root filesystem did not provide `mkfs.ext2`, `e2fsck`, or
  `fsck.ext2`; the implementation must include the required e2fsprogs tools.

Use ext2 for the first application-data filesystem implementation. It is the
only filesystem confirmed on the protected kernel that provides normal Linux
filesystem semantics on a MicroSD block partition. Add the required e2fsprogs
userspace programs before changing the media layout.

Ext2 does not provide a journal. Power-interruption, corruption, repair, and
reformat behavior must therefore pass physical testing before this ADR can be
accepted. If ext2 cannot meet the recovery requirements, stop implementation
and record a separate protected-kernel decision. Do not silently use the FAT or
exFAT boot filesystem for general application data.

Do not rely on MicroSD enumeration alone for the application-partition path.
The implementation should derive or expose a stable device path for partition 2
from the boot device selected by the initramfs.

Continue using the Nerves Runtime application-partition metadata contract.
However, do not use the standard `nerves_runtime` 0.13.13 initializer unchanged.
It formats the application partition whenever a read-write mount fails and does
not attempt filesystem repair first. A generic mount failure must not authorize
destructive reformatting.

Override `:nerves_runtime, :init_module` with an Atom Cam 2-specific one-shot
initializer that applies the following policy:

- If the early boot environment has already mounted `/data`, unmount it before
  checking the filesystem.
- Read the first 128 KiB of the application-data partition.
- Treat the partition as intentionally uninitialized only when all bytes in
  that region are `0xff`.
- Only the intentionally uninitialized state may trigger `mkfs.ext2`.
- Treat read errors, short reads, and all other partition contents as an
  existing or unknown filesystem state that must not be formatted
  automatically.
- For an existing filesystem, ensure that it is unmounted and run `e2fsck -p`
  before the first read-write mount. This returns quickly for a clean
  filesystem and checks one left unclean by an interrupted write. Ext2 can
  accept a mount while still containing directory-entry damage, so mount
  success alone is not an integrity check.
- Retry the read-write mount only when `e2fsck` returns status `0` or `1`.
- When the `e2fsck` status includes the reboot-required value `2`, leave
  `/data` unmounted and report that a reboot is required. This includes statuses
  `2` and `3`.
- For any other `e2fsck` status, or if the mount still fails after successful
  repair, leave `/data` unmounted and report the failure without formatting.

The first 128 KiB invalidation marker is part of the media lifecycle contract.
The fwup `complete` and factory-reset operations may create it deliberately.
Mount failure alone must never create or imply that state.

Move persistent service state to `/data`:

- NervesSSH host and user state
- NervesTime state
- Future application databases, caches, and durable configuration

Remove project-specific paths when the corresponding library defaults work with
the new `/data` layout. Otherwise, configure explicit paths beneath `/data`.

Keep these outside application data:

- Firmware slot and activation metadata
- Current firmware metadata
- Device provisioning
- Authorized keys supplied with the media
- Hostname supplied with the media
- Factory calibration
- Bootloader and kernel resources

Provisioning must be preserved independently by the fwup `upgrade` and
factory-reset tasks.

The initial partition-layout transition requires a complete media
reinstallation. An in-place repartitioning migration is not required for the
first implementation. The fwup `upgrade` task for firmware expecting `/data`
must reject media that still has the old one-partition flat-SD layout.

The migration procedure must clearly warn that runtime-only state, including the
current SSH host key, may be reset once unless it is backed up and restored
explicitly.

## Consequences

### Positive

- Applications can use the standard `/data` contract.
- Library-specific `/media/mmc` overrides can be removed.
- Firmware upgrades can preserve application data by design.
- Factory reset becomes a distinct, testable operation.
- Future databases and durable services gain Linux filesystem semantics.

### Negative

- The MicroSD layout changes and requires a complete reinstall.
- The ext2 data filesystem needs first-boot formatting and recovery behavior.
- Ext2 has no journal, so power interruption can require filesystem repair or
  reinitialization.
- Unrecoverable corruption can leave `/data` unavailable until explicit
  servicing or factory reset.
- Adding e2fsprogs increases the root filesystem size.
- The first migration may replace the current SSH host identity unless it is
  explicitly preserved.
- The boot/provisioning filesystem and application-data filesystem must be
  managed separately.
- The final application-partition path must be stable even if MicroSD device
  enumeration differs from the verified hardware sample.

## Data lifecycle

### Complete installation

- Create the dedicated data partition in the partition table.
- Invalidate its initial contents so first boot cannot reuse stale filesystem
  state from previously used media.
- Let the Atom Cam 2 initializer recognize the explicit invalidation marker,
  format the partition as ext2, and mount it at `/data`.
- Preserve only explicitly supplied device provisioning and media configuration.

The host-side `complete` task does not need to create a mounted filesystem. It
must leave a deterministic uninitialized partition that exercises the same
first-boot initialization and recovery behavior used in the field.

### Firmware upgrade

- Require the expected boot and data partition offsets before writing.
- Reject the old one-partition flat-SD layout.
- Do not format, invalidate, resize, or overwrite the data partition.
- Mount the existing data after booting the new firmware.
- Preserve application and service state.

### Factory reset

- Invalidate or clear only the data partition.
- Preserve the current firmware, protected kernel, device provisioning,
  authorized keys, hostname, and factory calibration.
- Reboot into the currently installed firmware.

ADR 0005 owns these application-data reset semantics and the initial
`factory-reset` operation. ADR 0006 may integrate the same operation with an A/B
firmware layout, but it must not redefine what persistent data is preserved.

### Filesystem recovery

Do not use mount failure as permission to reformat an existing filesystem.

For a partition that does not contain the explicit invalidation marker:

1. Ensure that it is unmounted.
2. Run `e2fsck -p`.
3. Mount it read-write only after status `0` or `1`.
4. Leave `/data` unmounted when the status includes the reboot-required value
   `2`, after an unrepaired error, after an operational failure, or after
   a mount failure.

The `e2fsck` exit status is a sum of condition values. The reboot-required value
`2` may therefore appear as status `2` or in combination with another value,
such as status `3`. The initializer must report that condition without mounting
or formatting the partition.

An operator may later choose an explicit factory reset when recovery is not
possible. Automatic recovery must favor preservation of potentially recoverable
application data over unattended destructive reinitialization.

Do not log application data, Wi-Fi credentials, authorized keys, SSH private
keys, or other secrets while diagnosing initialization or recovery.

## Scope boundary with ADR 0006

ADR 0005 includes:

- The dedicated application-data partition
- First-boot initialization and mounting
- `complete`, `upgrade`, and factory-reset data lifecycle
- Persistence paths for applications and runtime services

ADR 0005 does not include:

- A/B root-filesystem slots
- Active or pending slot selection
- Firmware validation or boot-attempt accounting
- Automatic rollback, manual revert, or prevent-revert behavior
- Enabling remote firmware upload

Those behaviors remain exclusively within ADR 0006.

## Verification strategy

The protected-kernel and current-userspace capability audit is recorded in
`docs/worklog/20260719-adr-0005-persistent-data-capability-audit.md`.

- Add and verify `mkfs.ext2`, `e2fsck`, and `fsck.ext2` before changing the
  partition layout.
- Confirm a stable application-partition path derived from the boot device.
- Confirm that only an all-`0xff` first 128 KiB region authorizes formatting.
- Confirm that read errors and non-marker content never authorize formatting.
- Confirm that an existing filesystem invokes `e2fsck -p` while unmounted and
  before its first read-write mount.
- Confirm that `e2fsck` statuses `0` and `1` permit a mount retry.
- Confirm that statuses containing the reboot-required value `2` and all
  failure statuses leave `/data` unmounted without invoking `mkfs.ext2`.
- Boot with an uninitialized data partition and confirm first-boot setup.
- Confirm `/data` is mounted read-write before dependent services start.
- Persist SSH state and time state under `/data`.
- Reboot and verify both remain unchanged.
- Apply an fwup upgrade and confirm test data survives.
- Confirm the upgrade task rejects old one-partition media.
- Apply a complete installation and confirm old data is reset.
- Run factory reset and confirm data is cleared without changing firmware or
  provisioning.
- Interrupt writes and boot repeatedly to test filesystem recovery.
- Confirm no current-firmware metadata is read from stale `/data` content.
- Confirm logs and reports do not expose secrets.

## Acceptance criteria

- `/data` is a dedicated writable application filesystem.
- Ext2 is supported by the protected kernel and passes physical
  power-interruption and recovery testing.
- Only the explicit application-partition invalidation marker authorizes
  automatic formatting.
- An existing or unknown filesystem is never reformatted after a mount or
  repair failure.
- Nerves Runtime reports the application partition accurately.
- NervesMOTD can report real application-partition usage.
- NervesSSH host keys persist using `/data`.
- NervesTime state persists using `/data`.
- `upgrade` preserves `/data` and rejects old one-partition media.
- `complete` and factory reset clear `/data` as documented.
- Provisioning remains separate and preserved.
- Application code no longer treats `/media/mmc` as general persistent storage.
- The protected kernel verification contract remains unchanged.

## References

- [Nerves FAQ: persistent data](https://hexdocs.pm/nerves/faq.html)
- [nerves_runtime filesystem initialization](https://hexdocs.pm/nerves_runtime/)
