# ADR 0005: Provide a standard persistent data partition

## Status

Proposed

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

## Decision

Add a dedicated writable application-data partition to the Atom Cam 2 MicroSD
layout and mount it at `/data`.

The partition must:

- Be separate from the boot and provisioning filesystem.
- Use a Linux filesystem supported reliably by the current kernel.
- Be initialized on first boot when necessary.
- Be mounted read-write before applications that depend on it start.
- Survive the fwup `upgrade` task.
- Be initialized or cleared by the fwup `complete` task.
- Be clearable through a standard factory-reset operation.

Prefer ext4 when kernel configuration and power-interruption testing confirm it
is suitable. If ext4 cannot meet the platform constraints, choose another Linux
filesystem through a follow-up decision rather than storing general application
data on the FAT boot filesystem.

Use `nerves_runtime` application-filesystem behavior where practical. Supply the
system metadata needed for Nerves Runtime to identify and mount the partition.

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
- Factory calibration
- Bootloader and kernel resources

Provisioning must be preserved independently by the fwup `upgrade` task.

The initial partition-layout transition requires a complete media
reinstallation. An in-place repartitioning migration is not required for the
first implementation. The migration procedure must clearly warn that
runtime-only state, including the current SSH host key, may be reset once unless
it is backed up and restored explicitly.

## Consequences

### Positive

- Applications can use the standard `/data` contract.
- Library-specific `/media/mmc` overrides can be removed.
- Firmware upgrades can preserve application data by design.
- Factory reset becomes a distinct, testable operation.
- Future databases and durable services gain Linux filesystem semantics.

### Negative

- The MicroSD layout changes and requires a complete reinstall.
- The data filesystem needs first-boot formatting and recovery behavior.
- Filesystem corruption handling may erase damaged application data.
- The first migration may replace the current SSH host identity unless it is
  explicitly preserved.
- The boot/provisioning filesystem and application-data filesystem must be
  managed separately.

## Data lifecycle

### Complete installation

- Create the data partition.
- Initialize it to an empty, known state.
- Preserve only explicitly supplied device provisioning.

### Firmware upgrade

- Do not format or overwrite the data partition.
- Mount the existing data after booting the new firmware.
- Preserve application and service state.

### Factory reset

- Clear the data partition.
- Preserve firmware, device identity, and factory provisioning.
- Reboot into the currently selected validated firmware.

### Filesystem recovery

Use Nerves Runtime's standard recovery behavior when it is compatible with the
chosen filesystem. A mount failure may trigger reformatting to recover a device
that cannot be serviced manually. This behavior must be documented because it
prioritizes device recoverability over retaining corrupted data.

## Verification strategy

- Boot with an uninitialized data partition and confirm first-boot setup.
- Confirm `/data` is mounted read-write before dependent services start.
- Persist SSH state and time state under `/data`.
- Reboot and verify both remain unchanged.
- Apply an fwup upgrade and confirm test data survives.
- Apply a complete installation and confirm data is reset.
- Run factory reset and confirm data is cleared without changing firmware or
  provisioning.
- Interrupt writes and boot repeatedly to test filesystem recovery.
- Confirm no current-firmware metadata is read from stale `/data` content.

## Acceptance criteria

- `/data` is a dedicated writable application filesystem.
- Nerves Runtime reports the application partition accurately.
- NervesMOTD can report real application-partition usage.
- NervesSSH host keys persist using `/data`.
- NervesTime state persists using `/data`.
- `upgrade` preserves `/data`.
- `complete` and factory reset clear `/data` as documented.
- Provisioning remains separate and preserved.
- Application code no longer treats `/media/mmc` as general persistent storage.

## References

- [Nerves FAQ: persistent data](https://hexdocs.pm/nerves/faq.html)
- [nerves_runtime filesystem initialization](https://hexdocs.pm/nerves_runtime/)
