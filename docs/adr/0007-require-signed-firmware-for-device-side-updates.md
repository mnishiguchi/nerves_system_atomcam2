# ADR 0007: Require signed firmware for device-side updates

## Status

Rejected on July 26, 2026

## Context

ADR 0006 introduces A/B firmware installation through fwup and the SSH
firmware subsystem. This ADR proposed making Ed25519 signatures mandatory for
every device-side update, with separate development and release keys, embedded
trust roots, release-key custody, key rotation, and an on-device fwup policy
wrapper.

That proposal is stricter and more operationally complex than the official
Nerves systems baseline:

- `mix firmware` normally produces an unsigned fwup archive.
- `nerves_ssh` normally exposes `ssh_subsystem_fwup`, which applies that archive
  with fwup.
- fwup signing and trusted public-key options are available when a product's
  threat model requires them, but they are not required by a standard Nerves
  system.

This project currently needs the behavior expected from an official Nerves
system, plus the minimum Atom Cam 2-specific work needed to update its A/B
application partitions safely.

## Decision

Do not require firmware signatures at this stage.

Use the ordinary Nerves workflow:

```sh
mix firmware
mix upload nerves.local
```

SSH public-key authentication controls access to the update endpoint. The
device uses fwup's archive and resource integrity checks, validates the firmware
platform and architecture, writes only the inactive application slot, verifies
the written root filesystem, and records the candidate as pending.

Keep the Atom Cam 2 A/B updater, health confirmation, and rollback behavior from
ADR 0006. Do not add a custom fwup wrapper, build alias, embedded signing trust
store, development/release key ceremony, or release signing manifest.

For Issue #12, this means:

- NervesSSH provides the authenticated transport.
- The custom SSH subsystem stages complete uploads under `/data` and cleans up
  interrupted transfers.
- Fwup and the Atom Cam 2 updater validate archive integrity, firmware metadata,
  the inactive-slot write, and the resulting root filesystem.
- The upload reports receiving, byte-count, installation, write-progress, and
  final success or failure information.

## Consequences

The system remains close to the official Nerves workflow and has fewer keys,
policies, wrappers, and recovery cases to operate.

SSH credentials must be protected because an administrator with update access
can install a well-formed firmware archive. Fwup integrity checks detect archive
or resource corruption, but they do not authenticate who produced an unsigned
archive.

Mandatory signing can be proposed again if the deployment threat model changes,
for example for a remotely managed fleet, untrusted artifact distribution, or a
requirement to authenticate releases independently of SSH access.

## Implementation evidence

The final repository and physical-device validation are recorded in
[`../worklog/20260726-adr-0007-standard-nerves-update-alignment.md`](../worklog/20260726-adr-0007-standard-nerves-update-alignment.md).

## References

- [`ssh_subsystem_fwup` update options](https://hexdocs.pm/ssh_subsystem_fwup/readme.html)
- [Nerves Runtime](https://hexdocs.pm/nerves_runtime/)
- [Issue #12: production firmware update delivery workflow](https://github.com/mnishiguchi/nerves_system_atomcam2/issues/12)
