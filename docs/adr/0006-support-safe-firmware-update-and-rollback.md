# ADR 0006: Support safe firmware update and rollback

## Status

Proposed

## Context

Remote firmware upload is currently rejected because the Atom Cam 2 media layout
has one active SquashFS root filesystem and no verified rollback mechanism.

Writing the running firmware location in place creates unacceptable failure
modes:

- Power loss can leave no bootable root filesystem.
- A validly written but defective firmware can enter a reboot loop.
- There is no previous firmware slot to select.
- There is no standard status, validation, or revert operation.
- The protected kernel has no verified atomic device-side replacement path.

Standard Nerves systems commonly use inactive-slot updates and provide fwup
operations for status, validation, revert, and prevent-revert.

ADR 0005 separately defines the persistent application-data partition and the
factory-reset semantics that clear application data while preserving firmware,
provisioning, and the protected kernel. This decision must integrate that
operation with the future A/B layout without redefining its data lifecycle.

The supported Atom Cam 2 boot chain is constrained by an externally supplied,
protected control kernel. That kernel includes the active vendor initramfs. The
vendor initramfs mounts the FAT partition and switches into the fixed file
`rootfs_hack.squashfs`.

The initramfs source under `board/atomcam2/initramfs/` documents and reproduces
the required handoff for possible future custom-kernel work. It is not the
initramfs embedded in the protected kernel used by the supported system.
Therefore, this repository cannot make the vendor initramfs select firmware
slots without replacing the protected kernel.

The protected kernel must remain unchanged. Its fixed
`rootfs_hack.squashfs` handoff can still support A/B firmware indirectly if that
file becomes a small boot manager that performs a second root-filesystem
handoff.

## Decision

Implement an A/B application-firmware model behind an immutable boot manager.

Keep the supported first-stage boot contract unchanged:

```text
U-Boot
  -> protected control kernel
  -> built-in vendor initramfs
  -> FAT partition
  -> rootfs_hack.squashfs
```

Change the role of `rootfs_hack.squashfs` from the application firmware to a
small boot-manager root filesystem. The boot manager must:

- Read rollback metadata from a dedicated raw region.
- Select application slot `a` or slot `b`.
- Mount the selected raw SquashFS application partition.
- Perform a second root-filesystem handoff into the selected application.
- Fall back to the last confirmed slot when the pending slot cannot be used.
- Provide an operator-visible recovery state when neither slot is bootable.

This architecture is conditional on a physical prototype proving that the
protected kernel and boot manager can perform the second handoff reliably. Do
not implement the full A/B update path until that prototype passes. If the
prototype fails, stop and revise this ADR rather than changing the protected
kernel or silently selecting another architecture.

### Intended media layout

Use the following conceptual layout after the prototype is proven:

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

The exact offsets, slot sizes, metadata-region size, and minimum supported
MicroSD capacity must be selected after measuring the prototype and defining
reasonable firmware-growth space.

The rollback-metadata region must be outside mounted filesystems and ordinary
provisioning files. It must not use `/data`, because slot selection occurs
before `/data` is mounted and application data must remain independent of
firmware activation.

The transition from the current two-partition layout requires a host-side
`complete` installation. In-place repartitioning is not required and must not be
attempted by the first implementation.

### Protected first-stage firmware

The protected control kernel and boot manager are shared first-stage firmware.
They must not be changed by device-side application updates.

The first safe device-side update implementation may write only:

- The inactive application slot.
- The dedicated rollback-metadata region after the candidate is verified.

It must not write:

- The protected control kernel.
- The boot-manager image.
- The FAT filesystem.
- Provisioning files.
- The active application slot.
- `/data`.

Updating the protected kernel, boot manager, or partition layout requires a
host-side `complete` installation until a separate safe activation mechanism is
proven.

### Firmware-slot metadata

Store only the state required for deterministic selection and rollback. At
minimum, the state must identify:

- The confirmed slot.
- An optional pending slot.
- Remaining boot attempts for the pending slot.
- A monotonically increasing generation.
- Firmware identifiers and checksums needed to reject stale or mismatched state.
- A checksum covering the metadata record.

Maintain two fixed-size metadata records. A state change must write the next
generation to the older or invalid record while leaving the current valid record
untouched. On boot, select the valid record with the highest generation.

An interrupted metadata write must therefore leave at least one usable previous
record. If neither record is valid, the boot manager must enter an explicit
recovery path rather than guessing which application slot to boot.

Prefer a small, purpose-built native utility for metadata parsing and updates.
Do not implement a generalized state framework without a concrete need.

### Slot selection and boot attempts

The boot manager must select slots as follows:

- When no slot is pending, boot the confirmed slot.
- When a slot is pending, persistently decrement its remaining-attempt count
  before handing control to it.
- If the pending slot cannot be mounted or fails structural validation, clear or
  reject the pending state and boot the confirmed slot.
- If no attempts remain, clear the pending state and boot the confirmed slot.
- Never overwrite or discard the confirmed slot merely because another slot is
  pending.

The initial implementation should use a small fixed attempt limit, such as three
boots. The exact value may be adjusted from physical-test evidence.

Boot-attempt accounting handles failures that cause a reboot. Recovery from a
firmware image that hangs indefinitely requires an independent reboot mechanism.
A usable hardware watchdog or equivalent mechanism must be verified before
unattended remote update can be considered safe.

### Candidate writing and activation

The currently running application slot must never be overwritten by an
`upgrade` task.

An upgrade must:

1. Determine the active and inactive application slots.
2. Stream the candidate root filesystem to the inactive raw slot.
3. Verify the complete destination image, checksum, size, and firmware metadata.
4. Leave the confirmed slot and rollback metadata unchanged if verification
   fails.
5. Record the verified inactive slot as pending using the redundant metadata
   protocol.
6. Reboot only after the pending state is durably recorded.

Separate internal slot-specific fwup tasks may be used if a checked wrapper must
choose the inactive destination. The public update path must not allow callers
to overwrite the active slot directly.

### Firmware health and validation

The application must validate newly booted firmware only after essential health
checks pass. At minimum:

- The OTP application starts.
- `/data` is mounted read-write.
- The expected firmware and slot metadata are available and consistent.
- The required network subsystem starts and configures the intended interface
  without an internal failure.
- The application remains healthy for a defined stabilization period.

External network reachability must not be required unless the product contract
explicitly requires it. A missing access point, DHCP server, or upstream network
must not by itself cause firmware rollback.

Validation promotes the running pending slot to the confirmed slot and clears
its pending state. The previous slot remains available until
`prevent-revert` is requested.

### Standard Nerves operations

Provide `/usr/share/fwup/ops.fw` tasks compatible with Nerves Runtime:

- `status`
- `validate`
- `revert`
- `prevent-revert`
- `factory-reset`

Use `Nerves.Runtime.FwupOps` and `Nerves.Runtime.validate_firmware/0` rather than
project-specific application APIs when the standard interfaces are available.
The Atom Cam 2 implementation may use custom fwup operations internally to
manage its dedicated raw metadata.

Retain the ADR 0005 `factory-reset` behavior. It must clear only `/data` and
must not change slot selection, validation state, application-slot contents,
provisioning, the boot manager, or the protected kernel.

### Persistent-data compatibility

Firmware rollback does not roll back `/data`.

The initial update policy therefore requires each candidate firmware to remain
backward-compatible with the existing `/data` format. Destructive or
irreversible application-data migrations are not supported by this decision.

A firmware image must not validate after beginning an irreversible migration
that would prevent the previous confirmed firmware from using `/data`. A future
need for irreversible migrations requires a separate design that explicitly
coordinates migration and rollback eligibility.

Do not build a generic migration framework until a concrete requirement exists.

### Remote update boundary

Remote firmware upload must remain rejected while the boot-manager prototype,
A/B implementation, watchdog behavior, complete physical failure matrix, and
ADR 0007 firmware-authentication requirements are unverified.

After all acceptance criteria pass, enable the existing SSH fwup subsystem so
that `mix upload` applies the checked inactive-slot `upgrade` path.

NervesHub is outside the scope of this decision.

## Consequences

### Positive

- The protected kernel and vendor initramfs remain unchanged.
- The vendor's fixed `rootfs_hack.squashfs` contract remains satisfied.
- Power loss while writing an inactive application slot does not destroy the
  confirmed firmware.
- Device-side updates do not modify the mounted FAT boot filesystem.
- Defective firmware can revert automatically after reboot or watchdog reset.
- Standard Nerves firmware status and rollback APIs become available.
- Persistent application data remains independent of firmware-slot activation.
- Factory-reset behavior remains consistent across the flat and A/B layouts.
- The boot manager can provide a recovery environment even when application
  slots are unusable.

### Negative

- The boot flow gains a second root-filesystem handoff that must be proven on
  physical hardware.
- The media layout changes and requires a complete reinstall.
- Two application slots and a boot manager require additional MicroSD capacity.
- The boot manager and slot-state utility become safety-critical components.
- `/data` moves from partition 2 to partition 4 and all related metadata and
  tests must be updated.
- Automatic recovery from a hung candidate depends on a verified watchdog or
  equivalent independent reboot mechanism.
- The protected kernel and boot manager remain outside remote updates initially.
- Validation policy must balance fast rollout against false success.
- Failure testing is extensive and requires repeated destructive hardware
  experiments.

## Scope boundary with ADR 0005

ADR 0006 owns:

- The immutable boot-manager handoff.
- A/B application-root-filesystem layout and activation.
- Active, pending, and confirmed slot state.
- Boot-attempt accounting and automatic rollback.
- `status`, `validate`, `revert`, and `prevent-revert`.
- The decision to enable remote firmware upload.
- Verification that `/data` survives update and rollback.

ADR 0006 does not own:

- Filesystem selection for `/data`.
- First-boot initialization or repair of `/data`.
- Which application and service state belongs under `/data`.
- Factory-reset preservation semantics.

Those application-data decisions remain in ADR 0005. Moving the data partition
to partition 4 is a layout integration detail and must preserve the ADR 0005
filesystem lifecycle and safety policy.

## Scope boundary with ADR 0007

ADR 0006 owns crash-safe inactive-slot writing, destination verification,
activation, validation, and rollback.

ADR 0007 owns firmware authenticity, trusted signing keys, signature
verification, and key rotation. Once device-side updates are enabled, a
candidate must satisfy ADR 0007 before any inactive-slot write begins. Signature
failure must leave both slot contents and rollback metadata unchanged.

## Boot and update lifecycle

### Confirmed boot

1. The vendor initramfs switches into the immutable boot manager.
2. The boot manager reads both metadata records.
3. The boot manager selects the newest valid state.
4. With no pending slot, it mounts and hands off to the confirmed slot.
5. The application mounts `/data` under the ADR 0005 policy.

### Pending boot

1. The boot manager reads a valid pending slot and remaining-attempt count.
2. It durably decrements the count before the application handoff.
3. It verifies and mounts the pending slot.
4. It hands off to the pending application.
5. The application performs health checks.
6. Successful validation promotes the pending slot to confirmed.
7. A reboot before validation consumes another attempt.
8. Exhausted attempts cause the boot manager to return to the previous confirmed
   slot.

### Manual revert

A manual revert must select the previous usable slot through the same redundant
metadata protocol. It must not copy firmware images or mutate `/data`.

### Prevent revert

`prevent-revert` may mark the previous slot reusable as the next inactive update
destination. It must not erase the running confirmed firmware before another
verified candidate exists.

## Power-interruption safety

The implementation must define and verify these outcomes:

- Power loss before candidate writing leaves the confirmed slot selected.
- Power loss during candidate writing leaves the confirmed slot and current
  metadata untouched.
- Power loss after candidate writing but before activation leaves the confirmed
  slot selected.
- Power loss while writing new metadata leaves the previous valid metadata
  record usable.
- Candidate checksum or structural validation failure never creates pending
  state.
- Power loss during validation may conservatively leave the candidate pending;
  it must not destroy the previous confirmed state.
- Power loss during `prevent-revert` must leave at least one bootable confirmed
  slot and one valid metadata record.

## Prototype gates

Before implementing the complete A/B update path, prove on physical Atom Cam 2
hardware that:

- The protected-kernel SHA-256 remains unchanged.
- The vendor initramfs enters the boot-manager `rootfs_hack.squashfs`.
- The boot manager can discover the MicroSD application partition reliably.
- The protected kernel can mount a raw SquashFS application partition.
- The boot manager can perform the second root-filesystem handoff.
- Required `/dev`, `/proc`, `/sys`, and FAT mounts remain usable after the
  handoff.
- The Nerves release starts normally from the application slot.
- `/data` initializes, repairs, and mounts under the ADR 0005 policy.
- Graceful reboot and poweroff remain reliable.
- A hardware watchdog or equivalent reboot mechanism is available and behaves
  predictably.

Failure of any foundational prototype gate must stop the A/B implementation and
trigger an ADR revision.

## Verification strategy

After the prototype passes, the physical failure matrix must include:

- Normal update to the inactive slot.
- Successful candidate validation.
- Preservation of the previous firmware until confirmation.
- Power loss before any inactive-slot write.
- Power loss during inactive-slot write.
- Power loss after write but before activation-state changes.
- Power loss while activation state is changing.
- Corrupt firmware resource.
- Incorrect firmware metadata.
- Root-filesystem mount failure.
- OTP release startup failure.
- Application health-check failure.
- Repeated reboot before validation.
- Candidate hang followed by watchdog recovery.
- Failure to write validation state.
- Corrupt or missing rollback slot.
- Corrupt rollback metadata copies.
- Manual revert.
- Prevent-revert after successful validation.
- Factory reset with both slots present.
- Upgrade with nearly full `/data`.
- Preservation of `/data` across successful update and rollback.
- Preservation of provisioning and FAT-side configuration.
- Upload interruption over SSH.
- Repeated reboot behavior without an infinite loop.
- Protected-kernel SHA-256 verification after every relevant workflow.

Every test must end in one of these explicit states:

- The previous confirmed firmware is bootable.
- The new firmware is bootable and can be validated.
- The immutable boot manager presents a documented recovery state because no
  application slot is usable.

No test may leave the media without a bootable boot manager.

Detailed investigation and physical-test evidence belong in dated files under
`docs/worklog/`.

## Acceptance criteria

- The protected control kernel remains unchanged and strictly verified.
- The immutable boot manager boots through the vendor's fixed FAT handoff.
- The boot manager reliably hands off to raw application slot `a` or `b`.
- The device reports confirmed, active, and pending firmware-slot state.
- `upgrade` writes only the inactive application slot.
- Device-side updates do not write partition 1, the boot manager, or the
  protected kernel.
- Interrupted slot writes leave the confirmed slot bootable.
- Interrupted metadata writes leave a previous valid record usable.
- New firmware is pending rather than immediately permanent.
- Failed validation automatically returns to the previous confirmed slot.
- Candidate hangs recover through a verified watchdog or equivalent mechanism.
- `status`, `validate`, `revert`, and `prevent-revert` work through standard
  Nerves Runtime APIs.
- The ADR 0005 `factory-reset` operation continues to clear only `/data` with
  both application slots present.
- `/data` survives successful update, rollback, manual revert, and
  `prevent-revert`.
- The previous firmware can still use `/data` after candidate rollback.
- The transition from the current layout is documented as a complete
  installation.
- `mix upload` remains disabled until the complete physical failure matrix
  passes and ADR 0007 firmware authentication is verified.
- After enablement, `mix upload` uses the checked inactive-slot `upgrade` path.

Do not mark this ADR `Accepted` until all acceptance criteria have been verified
on physical Atom Cam 2 hardware.

## References

- [Nerves Runtime fwup integration](https://hexdocs.pm/nerves_runtime/)
- [`Nerves.Runtime.FwupOps`](https://hexdocs.pm/nerves_runtime/Nerves.Runtime.FwupOps.html)
- [`ssh_subsystem_fwup`](https://hexdocs.pm/ssh_subsystem_fwup/readme.html)
- [`board/atomcam2/README.md`](../../board/atomcam2/README.md)
- [ADR 0005](0005-provide-standard-persistent-data-partition.md)
- [ADR 0007](0007-require-signed-firmware-for-device-side-updates.md)
