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
validate and retain the incoming fwup meta-uuid
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
mount the inactive SquashFS read-only and validate its boot structure
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
- The written candidate must mount as SquashFS and contain executable
  `/sbin/init`, an unmount command, and all boot-manager handoff mountpoints.
- The candidate UUID is validated and copied from the incoming fwup
  `meta-uuid`.
- Pending metadata is written only after the candidate verifies successfully.
- The existing confirmed slot remains unchanged until the candidate is healthy
  after reboot.
- Metadata changes continue to use the redundant generation-based record
  protocol.
- Interrupted candidate writes leave the previous confirmed firmware selected.
- Interrupted metadata writes leave the previous valid metadata record usable.
- Firmware operations use one device lock to prevent concurrent mutation.
- If a pending slot still fails the boot manager's structural checks, the boot
  manager atomically marks it bad and boots the confirmed slot in the same
  boot.

## Nerves Runtime integration

`Nerves.Runtime` continues to provide the application-facing API:

```elixir
Nerves.Runtime.firmware_slots()
Nerves.Runtime.validate_firmware()
Nerves.Runtime.revert()
Nerves.Runtime.FwupOps.prevent_revert()
Nerves.Runtime.FwupOps.factory_reset()
```

A custom KV backend maps the physically running slot from the boot report and
the current redundant metadata into standard Nerves keys:

```text
nerves_fw_active
a.nerves_fw_uuid
a.nerves_fw_validated
b.nerves_fw_uuid
b.nerves_fw_validated
```

It reads live redundant metadata when KV reloads because the boot report is a
boot-time snapshot and remains stale after successful confirmation.
NervesMOTD uses its standard target runtime, so it displays the active slot,
validation state, and fwup nickname/UUID without an Atom Cam-specific firmware
override.

A restricted fwup-compatible adapter maps only the standard operations to the
Atom Cam 2 command. It does not execute arbitrary commands from `ops.fw`.
It emits fwup's length-prefixed `WN`, `OK`, and `ER` frames so
`Nerves.Runtime.FwupOps` can decode status and errors normally.

## Candidate confirmation

The example application starts a temporary firmware-health worker. On a pending
boot it waits for the stabilization period and verifies:

- the required Nerves applications are started;
- `/data` is writable;
- the boot report identifies a valid running pending slot;
- the runtime active slot, firmware UUID, product, platform, and architecture
  match that slot's metadata;
- firmware validation state is still `:unvalidated`;
- `wlan0` is present and configured, without requiring Internet reachability;
- Nerves heart is supervising the hardware watchdog.

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
- malformed or missing firmware UUID rejection;
- candidate SquashFS mount and boot-structure validation before metadata
  activation;
- persistence of the incoming fwup UUID in candidate slot metadata;
- atomic rejection of a structurally invalid pending slot in the metadata
  codec;
- direct application-health tests proving that local health failures and
  metadata-confirmation failures reboot without confirming the candidate;
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

UUID and MOTD validation on the same camera additionally covered:

- `:unvalidated` and `Not validated (A)` while an uploaded slot was pending;
- automatic transition to `:validated` and `Valid (A)` without another reboot;
- active UUID and MOTD identity matching the uploaded fwup `meta-uuid`;
- a manual revert to Slot B with Slot B's UUID and a revert back to Slot A.

Final implementation validation additionally covered:

- installation of firmware version `0.1.1`, UUID `dynamic-trip`
  (`4fe22452-c5cd-507f-3474-2dffd129bd11`) through `mix upload`;
- automatic confirmation only after firmware metadata, `wlan0`, `/data`, and
  Nerves heart health checks passed;
- `nerves_heart` 2.5.0 supervising the `jz Watchdog` with a 5-second hardware
  timeout;
- a blocked heart callback causing a full kernel reboot, with boot ID changing
  from `60c6bcf3-3360-4439-affe-22afc68dd7ca` to
  `51c56f45-ac72-4430-892e-9f0b1e53ff6c`;
- preservation of the confirmed Slot B and firmware UUID after watchdog
  recovery;
- a standard `Nerves.Runtime.revert/0` round trip from Slot B to Slot A and back
  to Slot B;
- interactive NervesMOTD output showing `dynamic-trip`, its UUID, `Valid (B)`,
  and `atomcam2 mipsel`.

The JZ watchdog driver reports `wdt_last_boot: :power_on` after watchdog reset,
so the changed kernel boot ID and reset uptime are the physical reset evidence.

The final tested firmware was Slot B version `0.1.1`, UUID `dynamic-trip`
(`4fe22452-c5cd-507f-3474-2dffd129bd11`).
The final metadata state was:

```text
generation=00000000000000000046
confirmed_slot=B
pending_slot=-
pending_attempts=000
slot_a_status=valid
slot_a_firmware_id=bebf9516-388f-5579-c661-e6ea6f68752f
slot_a_sha256=1710409cec4c8f641009c13a30c562028bc0ef1f6d7c5c58c0df14a86da3cbd5
slot_b_status=valid
slot_b_firmware_id=4fe22452-c5cd-507f-3474-2dffd129bd11
slot_b_sha256=102697efa2a490ad4596daf5be42b4a1bbec67748e67bb5166413e5badf2a325
```

## Physical validation still required

Before publishing this as a production-supported OTA path, validate on a real
Atom Cam 2:

- `Nerves.Runtime.FwupOps.prevent_revert/0`;
- a host-side complete install of the final boot manager followed by physical
  malformed-pending-slot same-boot fallback validation;
- power interruption during transfer, slot writing, verification, metadata
  commit, pending boot, and confirmation;
- recovery from an application that repeatedly crashes;
- factory reset with both slots present and the complete `/data`, provisioning,
  and protected-kernel preservation matrix;
- ADR 0007 firmware-signature enforcement.
