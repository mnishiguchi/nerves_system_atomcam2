# ADR: Separate application development from system maintenance

## Status

Accepted on July 16, 2026.

## Context

A regular Nerves application normally consumes a prebuilt Nerves system artifact. Application developers fetch Elixir dependencies, build firmware, install it, and later upload application updates without rebuilding Buildroot, Linux, or the cross-compilation toolchain.

The Atom Cam 2 port is still in the system-development stage. Reproducing the first verified ping and SSH baseline required several platform-specific steps:

- Build and select a MIPS32R2 soft-float toolchain without DSP ASE.
- Package that toolchain as a local Buildroot archive.
- Build the custom Nerves system from source.
- Apply a narrow VintageNet compatibility change for Linux 3.10 headers.
- Preserve the vendor kernel and initramfs boot handoff.
- Create and install a flat-file MicroSD payload rather than a conventional Nerves disk image.

These steps are appropriate for a system maintainer, but they make ordinary application development unnecessarily fragile. Mixing system preparation with application changes also made regressions difficult to isolate because toolchain archives, cached system artifacts, dependency patches, application releases, and SD payloads could all change at once.

## Decision

Separate the repository workflow into two explicit roles.

### Application development

The intended application workflow is:

```sh
mix setup
mix firmware
mix atomcam2.install
```

Later application-only updates should use `mix upload` when the update path is proven safe.

Application developers must not be required to:

- Build Buildroot or Linux.
- Construct the cross-toolchain archive.
- Patch dependency source manually.
- Understand the Atom Cam 2 vendor boot chain.
- Select between intermediate and final SquashFS images.

The application should consume a reusable prebuilt `nerves_system_atomcam2` artifact. Any unavoidable target compatibility behavior should be supplied by that system artifact, an upstream fix, or a deliberately maintained dependency rather than an undocumented manual edit.

### System maintenance

System maintainers remain responsible for:

- Building and validating the custom toolchain.
- Preparing the Buildroot toolchain archive.
- Maintaining the kernel, initramfs, rootfs overlay, and vendor Wi-Fi integration.
- Maintaining or upstreaming the VintageNet Linux 3.10 compatibility change.
- Producing, testing, caching, and publishing the system artifact.
- Preserving a known-good recovery payload and hardware verification procedure.

These operations must remain explicit and independently testable. Expensive or destructive preparation must not run silently as a side effect of every `mix firmware` invocation.

### Installation

Use a dedicated Atom Cam 2 installation command while the vendor flat-file MicroSD contract cannot be represented safely by the standard Nerves burner.

The intended command is:

```sh
mix atomcam2.install
```

It should validate the final application payload, back up the current SD files, install the required flat files, synchronize writes, and report the recovery location. Adopting `mix firmware.burn` remains possible only after the resulting behavior is equally clear and safe.

### Transition

Until the prebuilt system artifact exists, the README must distinguish one-time system preparation from the repeated application loop.

The application now provides:

```sh
mix setup
mix firmware
mix atomcam2.install
```

`mix setup` currently fetches dependencies and applies the Linux 3.10 VintageNet compatibility patch through the repository script. `mix atomcam2.install` delegates to the validated flat-SD installer and keeps backup and installation safety checks in one place.

System maintainers still prepare the local toolchain archive separately:

```sh
./scripts/prepare-toolchain-archive.sh
```

These commands describe the current transitional implementation, not the complete long-term application interface.

## Consequences

Application development can converge on the familiar Nerves workflow and avoid rebuilding or modifying platform internals for ordinary changes.

System builds remain more involved, but their complexity is isolated, documented, and suitable for reproducible release automation.

Publishing a system artifact introduces artifact-versioning and release-maintenance work. A dedicated installation task is also target-specific. These costs are accepted because they are safer and clearer than exposing Buildroot internals and the vendor SD contract to every application developer.

The current repository remains transitional until the following work is complete:

- Publish or otherwise distribute a reusable system artifact.
- Replace the locally applied VintageNet patch with an upstream fix or deliberately maintained dependency.
- Prove a safe application update path for `mix upload`.
