# ADR 0004: Adopt fwup for standard media workflows

## Status

Accepted

## Context

The Atom Cam 2 firmware build produces a Nerves `.fw` bundle, but installation
currently uses the custom `mix atomcam2.install` task to copy files into a
mounted MicroSD filesystem.

That workflow protects the known boot contract, but it differs from the standard
Nerves host workflow:

- `mix firmware.burn` is not the primary installation command.
- `mix burn` cannot author the supported MicroSD layout directly.
- `mix firmware.image` cannot produce the complete manufacturing image.
- The media layout is described across shell scripts and installer code rather
  than by `fwup.conf`.
- A future on-device upgrade cannot share the same authoritative update tasks.

Nerves conventionally uses fwup tasks named `complete` and `upgrade`.
`complete` writes the full media layout, while `upgrade` changes only the
software resources that must be replaced and preserves application data.

## Decision

Make `fwup.conf` the authoritative description of the Atom Cam 2 MicroSD
installation and upgrade workflow.

Provide at least these tasks:

### `complete`

The `complete` task must initialize supported media and write every resource
required to boot a newly prepared device:

- The verified Atom Cam 2 control kernel
- The SquashFS root filesystem
- Hostname and authorized-key provisioning
- Wi-Fi provisioning
- The partition and filesystem layout required by the current platform design

The task may initialize or clear application data, consistent with standard
Nerves complete-install semantics.

The generated `.fw` bundle is authoritative for the exact firmware identity,
including its fwup metadata UUID.

At runtime, product, version, platform, and architecture are derived from the
compiled application configuration and exposed through an in-memory
`Nerves.Runtime.KV` backend. The runtime must not read or trust
`nerves-firmware-metadata.conf` from the FAT filesystem because an upgrade
preserves non-firmware files and may therefore retain stale metadata from an
older installation.

The flat-SD runtime cannot safely recover the exact bundle UUID after
installation. The MOTD therefore reports `UUID unavailable` and identifies the
active layout as `Flat SD` rather than implying an A/B partition state.

The FAT-side metadata file remains optional and is not part of the safe fwup
media contract. Fwup calculates `meta-uuid` from the completed archive metadata,
while ordinary file-resource contents are fixed when the archive is created.
The implementation must not require unsafe commands or post-write mutation
solely to synthesize that compatibility file.

### `upgrade`

The `upgrade` task must update only firmware-owned resources and preserve:

- Device provisioning
- Authorized access configuration
- Persistent application data
- Device identity
- Any update state required by later rollback support

The initial implementation may update the existing single firmware location.
ADR 0006 will extend this task to target an inactive firmware slot.

Support the standard host commands:

```text
mix firmware.burn
mix burn
mix firmware.image
```

`mix firmware.image` must create a raw image that can be written byte-for-byte
to compatible media.

Retain `mix atomcam2.install` temporarily as a compatibility wrapper. After
hardware parity is proven, it must delegate to fwup rather than maintain a
second media-writing implementation. It may then be deprecated in a separate,
small change.

Keep remote firmware upload rejected during this ADR. Standard host-side media
writing does not by itself prove that an on-device update is safe.

## Consequences

### Positive

- Nerves-standard host commands become available.
- `fwup.conf` becomes the single source of truth for media writing.
- Manufacturing images can be created without mounting and copying files.
- The same firmware bundle can later support safe device-side upgrades.
- Device and media validation can be centralized in fwup tasks.

### Negative

- The current copying workflow must be represented accurately in fwup syntax.
- Media-layout mistakes can prevent the device from booting.
- A compatibility period will temporarily retain `mix atomcam2.install`.
- The complete and upgrade paths require separate destructive and
  preservation-focused hardware tests.

## Safety requirements

The implementation must:

- Verify the protected kernel SHA-256 before packaging or writing it.
- Reject media smaller than the supported minimum.
- Refuse obviously unsafe targets such as the host root device.
- Require explicit confirmation unless a supported noninteractive flag is used.
- Keep firmware resources and provisioning resources clearly separated.
- Avoid copying secrets into build logs.
- Verify the generated image before writing physical media.
- Preserve the current known-good custom installer until fwup parity is proven.

## Verification strategy

Test the following independently:

### Image construction

- Build the `.fw` bundle.
- Create a raw image with `mix firmware.image`.
- Inspect the image partition table and required files.
- Write the image using a standard block-copying tool.
- Boot the device.

### Complete installation

- Run `mix firmware.burn` against blank or disposable media.
- Confirm every required boot and provisioning resource.
- Boot and verify Wi-Fi, SSH, discovery, and time.
- Verify firmware identity directly from the generated `.fw` bundle.

### Upgrade installation

- Create persistent test data.
- Apply `mix burn --task upgrade`.
- Confirm the new firmware boots.
- Confirm provisioning and persistent test data remain unchanged.

### Compatibility wrapper

- Run `mix atomcam2.install`.
- Confirm it delegates to the same fwup task and produces an equivalent result.
- Confirm there is no separate file-copying implementation after migration.

## Acceptance criteria

- `fwup.conf` fully describes the supported media layout.
- `mix firmware.burn` prepares bootable Atom Cam 2 media.
- `mix burn --task upgrade` preserves non-firmware state.
- `mix firmware.image` creates a bootable raw image.
- Firmware identity remains queryable from the generated `.fw` bundle.
- The FAT-side metadata compatibility file is not required for media parity.
- The protected kernel verification remains enforced.
- The custom installer delegates to fwup or is removed after a documented
  deprecation period.
- Remote upload remains disabled until ADR 0006 is implemented and verified.

## References

- [`mix firmware.burn`](https://hexdocs.pm/nerves/Mix.Tasks.Firmware.Burn.html)
- [`mix burn`](https://hexdocs.pm/nerves/Mix.Tasks.Burn.html)
- [`mix firmware.image`](https://hexdocs.pm/nerves/Mix.Tasks.Firmware.Image.html)
- [Nerves advanced fwup configuration](https://hexdocs.pm/nerves/advanced-configuration.html)
