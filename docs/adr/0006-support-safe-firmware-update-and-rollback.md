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

The Atom Cam 2 already boots through a fixed control kernel with an initramfs,
which can participate in root-filesystem slot selection without changing the
vendor bootloader.

## Decision

Implement an A/B root-filesystem update model.

Maintain two independent SquashFS firmware slots:

- Slot `a`
- Slot `b`

The currently running slot must never be overwritten by an `upgrade` task.
An upgrade writes and verifies the inactive slot, then records it as the pending
slot for the next boot.

Store firmware-slot state in a small dedicated metadata region that is separate
from `/data` and ordinary provisioning files. The state representation must be
redundant or otherwise resilient to interrupted writes and must include enough
information to determine:

- Active slot
- Pending next slot
- Validation state
- Remaining boot attempts or equivalent rollback state
- A monotonically increasing generation or equivalent stale-record protection

The control initramfs must select the root filesystem using this state.

A pending firmware receives a bounded number of boot attempts. If it is not
validated successfully, the boot path must automatically return to the previous
validated slot.

The application must validate newly booted firmware only after essential health
checks pass. At minimum:

- The OTP application starts.
- `/data` is mounted read-write.
- The expected firmware metadata is available.
- VintageNet starts and the required interface is configured.
- The application remains healthy for a defined stabilization period.

Provide `/usr/share/fwup/ops.fw` tasks compatible with Nerves Runtime:

- `status`
- `validate`
- `revert`
- `prevent-revert`

Retain the ADR 0005 `factory-reset` operation in the same standard fwup
operations interface. It must continue to clear only `/data` and must not change
slot selection, validation state, firmware contents, provisioning, or the
protected kernel.

Use `Nerves.Runtime.FwupOps` and `Nerves.Runtime.validate_firmware/0` rather than
project-specific application APIs when the standard interfaces are available.

The first safe device-side update implementation updates the root filesystem
only. The protected control kernel remains shared and is updated only through a
host-side complete installation until a separate atomic kernel-activation
mechanism is proven.

After the full failure matrix passes, enable the existing SSH fwup subsystem so
that `mix upload` applies the standard `upgrade` task. Until then, remote upload
must remain rejected.

NervesHub is outside the scope of this decision.

## Consequences

### Positive

- Power loss while writing an inactive root filesystem does not destroy the
  running firmware.
- Defective firmware can revert automatically.
- Standard Nerves firmware status and rollback APIs become available.
- `mix upload` can eventually use the same fwup upgrade contract as host-side
  updates.
- Persistent application data remains independent of firmware-slot activation.
- Factory-reset behavior remains consistent across the flat and A/B layouts.

### Negative

- Two root-filesystem slots require additional MicroSD capacity.
- The initramfs and slot-state implementation become safety-critical.
- The protected kernel remains outside remote updates initially.
- Validation policy must balance fast rollout against false success.
- Failure testing is extensive and requires repeated destructive hardware
  experiments.

## Scope boundary with ADR 0005

ADR 0006 owns:

- A/B root-filesystem layout and activation
- Active, pending, and validated slot state
- Boot-attempt accounting and automatic rollback
- `status`, `validate`, `revert`, and `prevent-revert`
- The decision to enable remote firmware upload

ADR 0006 does not own:

- Filesystem selection for `/data`
- First-boot initialization of `/data`
- Which application and service state belongs under `/data`
- Factory-reset preservation semantics

Those application-data decisions remain in ADR 0005. ADR 0006 must preserve and
verify them when both firmware slots are present.

## Update lifecycle

1. Determine the active and inactive slots.
2. Stream the new root filesystem to the inactive slot.
3. Verify size, checksum, and firmware metadata.
4. Record the inactive slot as pending for the next boot.
5. Reboot.
6. Boot the pending slot with a limited attempt count.
7. Run application health checks.
8. Validate the slot.
9. Keep the previous slot available until `prevent-revert` is requested.

If boot or validation fails, select the previous validated slot automatically.

## Failure matrix

The implementation must test at least:

- Power loss before any inactive-slot write
- Power loss during inactive-slot write
- Power loss after write but before activation state changes
- Power loss while activation state is changing
- Corrupt firmware resource
- Incorrect firmware metadata
- Root filesystem mount failure
- OTP release startup failure
- Application health-check failure
- Repeated reboot before validation
- Manual revert
- Prevent-revert after successful validation
- Factory reset with both slots present
- Upgrade with nearly full `/data`
- Upload interruption over SSH

Every test must end in either:

- The previous validated firmware booting, or
- The new firmware booting and being validatable

No test may leave the media with neither slot bootable.

## Acceptance criteria

- The device reports active and pending firmware slots.
- `upgrade` writes only the inactive slot.
- Interrupted writes leave the active slot bootable.
- New firmware is initially pending rather than immediately permanent.
- Failed validation automatically returns to the previous slot.
- `status`, `validate`, `revert`, and `prevent-revert` work through standard
  Nerves Runtime APIs.
- The ADR 0005 `factory-reset` operation continues to clear only `/data` with
  both firmware slots present.
- `/data` survives successful upgrade and rollback.
- `mix upload` remains disabled until the complete failure matrix passes.
- After enablement, `mix upload` uses the standard fwup `upgrade` task.
- Device-side updates do not replace the protected kernel.

## References

- [Nerves Runtime fwup integration](https://hexdocs.pm/nerves_runtime/)
- [`Nerves.Runtime.FwupOps`](https://hexdocs.pm/nerves_runtime/Nerves.Runtime.FwupOps.html)
- [`ssh_subsystem_fwup`](https://hexdocs.pm/ssh_subsystem_fwup/readme.html)
