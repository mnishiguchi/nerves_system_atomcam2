# ADR 0006: `mix upload` OTA implementation

## Date

2026-07-25

## Goal

Connect the standard Nerves `mix upload` transport to the Atom Cam 2 A/B boot
and rollback foundation without allowing callers to select or overwrite an
application slot directly.

## Implemented path

```text
MIX_TARGET=atomcam2 mix upload nerves.local
|
v
NervesSSH `fwup` subsystem
|
v
Atomcam2NervesApp.FirmwareUploadSubsystem
|
v
run updater precheck
|
v
stage the SSH stream under /data
|
v
close the staged file on SSH EOF
|
v
/usr/bin/atomcam2-firmware-update install
|
v
validate firmware metadata and extract rootfs.img
|
v
select the inactive application slot
|
v
fwup task atomcam2-slot
|
v
verify the complete written rootfs checksum
|
v
write redundant pending boot metadata
|
v
reboot through the normal SSH upload success callback
```

The public device-side command is:

```text
/usr/bin/atomcam2-firmware-update
```

Supported operations:

```text
precheck
install FIRMWARE
status
confirm
revert
prevent-revert
reject-pending
factory-reset
```


## SSH subsystem process contract

The subsystem runs the updater precheck when the SSH channel opens. It writes
incoming chunks to an exclusive file under `/data/atomcam2-firmware-update`,
closes that file when the client sends SSH EOF, and invokes the updater in a
linked process so the channel remains responsive while installation runs.

Updater output and exit status are returned to the SSH client. Only a zero exit
status closes the channel as successful and schedules a reboot. Failed or
interrupted transfers remove the staged file and do not reboot the device.

The custom subsystem is required because the firmware must be fully staged and
closed before validation. The generic `ssh_subsystem_fwup` port integration
expects fwup itself to detect the end of a firmware stream and does not close a
wrapper process's stdin on SSH EOF.

## Safety properties

- The caller cannot select Slot A or Slot B.
- The running and confirmed slot must agree before installation.
- A new installation is rejected while another pending slot exists.
- Only the inactive raw application partition is passed to the internal fwup
  task.
- The candidate partition is verified against the extracted rootfs SHA-256
  before metadata activation.
- Pending metadata is written only after the candidate verifies successfully.
- The existing confirmed slot remains unchanged until the candidate is healthy
  after reboot.
- Metadata changes continue to use the redundant generation-based record
  protocol.
- Interrupted candidate writes leave the previous confirmed firmware selected.
- Interrupted metadata writes leave the previous valid metadata record usable.
- Firmware operations use one device lock to prevent concurrent mutation.

## Nerves Runtime integration

`Nerves.Runtime` continues to provide the application-facing API:

```elixir
Nerves.Runtime.firmware_slots()
Nerves.Runtime.validate_firmware()
Nerves.Runtime.revert()
Nerves.Runtime.FwupOps.prevent_revert()
Nerves.Runtime.FwupOps.factory_reset()
```

A restricted fwup-compatible adapter maps only the standard operations to the
Atom Cam 2 command. It does not execute arbitrary commands from `ops.fw`.
It emits fwup's length-prefixed `WN`, `OK`, and `ER` frames so
`Nerves.Runtime.FwupOps` can decode status and errors normally.

## Candidate confirmation

The example application starts a temporary firmware-health worker. On a pending
boot it waits for the stabilization period and verifies:

- the required Nerves applications are started;
- `/data` is writable;
- the boot report identifies the running slot as the pending slot.

The worker then calls `Nerves.Runtime.validate_firmware/0`, which confirms the
slot through the same metadata protocol.

If the local checks or confirmation fail, the device reboots so the pending
attempt policy can retry and eventually fall back. A confirmed application also
clears an exhausted pending state by marking that candidate bad.

## Validation completed in development

The shell test covers:

- update precheck;
- inactive Slot B installation from confirmed Slot A;
- active-slot preservation;
- candidate checksum verification;
- pending activation;
- confirmation;
- manual revert;
- prevent-revert;
- exhausted pending-candidate rejection;
- incompatible platform rejection;
- SSH upload subsystem integration on physical hardware;
- framed Nerves Runtime operations status and errors.

## Physical validation completed

Validation on an Atom Cam 2 on 2026-07-25 covered:

- target-side fwup and unzip availability;
- complete standard `mix upload nerves.local` cycles from confirmed Slot B to
  inactive Slot A and from confirmed Slot A to inactive Slot B;
- full candidate SHA-256 verification before metadata activation;
- upload success propagation and automatic reboot;
- health-based candidate confirmation;
- direct `Nerves.Runtime.FwupOps.status/0` and
  `Nerves.Runtime.firmware_slots/0` results for both slots;
- framed adapter errors through `Nerves.Runtime.FwupOps`;
- `Nerves.Runtime.revert/0` in both slot directions, including reboot and
  health-based confirmation.

The final tested firmware was version `0.1.1`, UUID `toy-cup`
(`eb377d26-74e3-54ff-b10f-476f771d546c`). Both slots contained rootfs SHA-256
`5428a0df2e36b0b1e619bd25083c493ece7b0cb0b3be42e3ecfcd8b8538b8434`.
The final metadata state was:

```text
generation=00000000000000000025
confirmed_slot=A
pending_slot=-
pending_attempts=000
```

## Physical validation still required

Before publishing this as a production-supported OTA path, validate on a real
Atom Cam 2:

- `Nerves.Runtime.FwupOps.prevent_revert/0`;
- power interruption during transfer, slot writing, verification, metadata
  commit, pending boot, and confirmation;
- recovery from an application that repeatedly crashes;
- watchdog recovery from a candidate that hangs without rebooting;
- ADR 0007 firmware-signature enforcement.
