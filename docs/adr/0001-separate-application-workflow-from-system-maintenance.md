# ADR: Separate application development from system maintenance

## Status

Accepted on July 16, 2026.

Implementation is prepared in source. Closure requires successful local compilation,
publishing the `v0.1.0` release artifacts, and verifying a clean-checkout build
and hardware boot.

## Context

A regular Nerves application consumes prebuilt system and toolchain artifacts.
Application developers should fetch dependencies, build firmware, and install it
without rebuilding Buildroot, Linux, or the cross-compilation toolchain.

The initial Atom Cam 2 port mixed application and system concerns. Reproducing
ping and SSH required a custom MIPS32R2 soft-float toolchain, a local Buildroot
archive, a Linux 3.10 compatibility edit to VintageNet source, and a target-
specific flat-file MicroSD installation procedure.

The target also differs from a conventional Nerves disk layout. It boots vendor-
named kernel and SquashFS files from a FAT partition that is mounted by the
running system.

## Decision

Separate the workflow into application and system-maintainer responsibilities.

### Application development

The supported workflow is:

```sh
mix setup
mix firmware
mix atomcam2.install
```

`mix setup` retrieves dependencies only. It must not build Buildroot, construct a
toolchain archive, or modify dependency source.

The example application consumes the tagged `nerves_system_atomcam2` Git source.
That package resolves matching prebuilt system and Atom Cam 2 custom toolchain
artifacts from GitHub Releases.

Maintainers can select the local system source explicitly with:

```sh
export ATOMCAM2_SYSTEM_SOURCE=local
```

### Target compatibility

Linux 3.10 compatibility belongs to the Nerves system rather than the
application. A small Buildroot package installs
`atomcam2-linux-3.10-compat.h` into the system staging sysroot. The system's
target compiler flags include that header, allowing VintageNet to compile
without editing `deps/vintage_net`.

### Installation

Use `mix atomcam2.install` for installation and application updates. It delegates
to the repository's validated flat-SD installer, which validates the payload,
backs up existing files, installs and verifies the required files, and
synchronizes writes.

### Remote updates

`mix upload` is unsupported. The current fwup `upgrade` task would write files on
the same FAT partition mounted by the running system, and that operation has not
been proven safe. The application configures the fwup SSH subsystem with a
precheck that rejects remote updates.

A future ADR may enable remote updates after the storage and boot design provides
a demonstrably safe update boundary.

### System maintenance and release

System maintainers are responsible for:

- Building and validating the MIPS32R2 soft-float toolchain without DSP ASE.
- Preparing the Buildroot input archive.
- Maintaining Linux, initramfs, rootfs overlays, and vendor Wi-Fi integration.
- Building the custom toolchain and system release artifacts.
- Publishing both artifacts under the release tag matching their package version.
- Running isolated release verification and hardware verification.

`scripts/release-artifacts.sh` builds both artifacts. Its explicit `--publish`
option creates the GitHub release, and `--verify` clones that release into an
isolated directory and builds the example application without local system or
toolchain overrides.

## Consequences

Application builds use the familiar Nerves dependency and firmware workflow and
avoid rebuilding or modifying platform internals.

System releases now include two coordinated artifacts: the Nerves system and the
Atom Cam 2 custom toolchain. Their versions and release tag must remain aligned.

Offline MicroSD installation remains target-specific, but it is explicit and
safe. Remote updates remain unavailable rather than exposing an unverified
in-place write path.

## Closure criteria

This ADR can be marked implemented after all of the following are recorded:

- `v0.1.0` contains the system and custom toolchain artifacts.
- `scripts/release-artifacts.sh --verify` succeeds with isolated Nerves caches.
- The resulting payload boots on Atom Cam 2 hardware.
- `nerves.local`, ping, SSH, Toolshed, and `mix atomcam2.install` remain working.
- An attempted remote fwup upload is rejected by the target precheck.
