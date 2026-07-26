# ADR 0007: standard Nerves update alignment

## Date

2026-07-26

## Outcome

ADR 0007 was rejected after comparing its mandatory-signing proposal with the
official Nerves systems baseline.

The supported application workflow remains:

```sh
mix firmware
mix upload nerves.local
```

Firmware signing remains an optional fwup capability. This project does not add
a signing build alias, embedded trust store, device-side fwup policy wrapper,
release-key ceremony, or key-rotation procedure without a deployment threat
model that requires them.

The Atom Cam 2-specific A/B updater remains necessary because the protected
kernel and custom media layout do not expose the ordinary Nerves application
partitions. SSH public-key authentication authorizes updates. Fwup archive and
resource integrity, firmware metadata checks, inactive-slot selection, written
rootfs verification, health confirmation, and rollback provide the baseline
delivery and installation checks.

## Issue #12 coverage

- Firmware transport: NervesSSH firmware subsystem.
- Update authorization: SSH public-key authentication.
- Candidate validation: fwup integrity plus platform, architecture, UUID,
  destination, and rootfs checks.
- Installation: inactive application slot only.
- Interrupted transfer handling: staged file cleanup without reboot.
- Progress and failures: receiving phase, byte count, installing phase, fwup
  write progress, updater output, and SSH exit status.

## Verification

- `MIX_TARGET=host mix test`: 23 tests passed.
- `mix smoke`: repository smoke checks and updater regression matrices passed.
- Target `mix firmware`: built a valid fwup archive without a signature.
- Rootfs inspection: `/usr/bin/fwup` is the packaged fwup 1.16.0 ELF binary;
  no signing trust store or policy-wrapper backup is present.
- A one-time transition archive signed for the previously installed
  experimental updater booted in Slot A and validated successfully.
- A subsequent ordinary unsigned `mix upload nerves.local` wrote Slot B,
  reported `receiving`, `installing`, and fwup write progress, rebooted, and
  validated successfully.

Final device state:

```text
active_slot=B
next_slot=B
validation=validated
firmware_uuid=02ce88e8-71c3-5665-11d0-60f423dfe860
```
