# ADR 0001 application workflow implementation

## Context

ADR 0001 separates ordinary application development from maintenance of the custom Atom Cam 2 Nerves system.

Before this work, the example application depended on several repository-local operations:

- Building the custom Nerves system from source
- Selecting a locally installed toolchain
- Modifying the downloaded `vintage_net` dependency
- Using repository-specific scripts to install the MicroSD payload
- Relying on local system artifacts that could not be reproduced from a clean checkout

The intended application workflow is closer to a normal Nerves project:

```sh
mix setup
mix firmware
mix atomcam2.install
```

System and toolchain maintenance may remain specialized, but those details should not be part of regular application development.

## Implemented structure

### Reusable toolchain package

A Nerves toolchain package was added under `toolchain/`.

It defines the custom Atom Cam 2 MIPS toolchain as a normal Nerves toolchain dependency and supports retrieving its artifact from GitHub releases.

The main system package now depends on:

```elixir
{:nerves_toolchain_atomcam2, path: "toolchain", runtime: false}
```

The source and release workflow for the toolchain are kept in the system repository because they must be versioned together.

### Reusable system artifact

The system package now declares GitHub releases as an artifact source.

The example application uses the released system by default:

```elixir
{:nerves_system_atomcam2,
 github: "mnishiguchi/nerves_system_atomcam2",
 tag: "v0.1.0",
 runtime: false,
 targets: :atomcam2}
```

Local system development remains available explicitly through:

```sh
export ATOMCAM2_SYSTEM_SOURCE=local
```

This avoids coupling ordinary application development to the system source tree while retaining a clear maintenance path.

### Linux 3.10 compatibility support

The application previously patched the downloaded `vintage_net` source to work with the Atom Cam 2 Linux 3.10 headers.

That mutation was removed.

A small Buildroot package now installs an Atom Cam 2 compatibility header into the system staging directory:

```c
#ifndef IFA_FLAGS
#define IFA_FLAGS 8
#undef IFA_MAX
#define IFA_MAX IFA_FLAGS
#endif
```

The system compiler flags automatically include this header.

This keeps Linux compatibility inside the system package, where platform-specific compiler and header behavior belongs. A clean `vintage_net` dependency now compiles without modifying files under `deps/`.

### Installation task

`mix atomcam2.install` was moved from the example application into the system package.

The task:

- Locates the generated flat MicroSD payload
- Validates all required files
- Finds the partition labeled `ATOMCAM2`
- Creates a timestamped backup
- Installs the new payload
- Verifies the installed files

The supported application workflow is now:

```sh
mix setup
mix firmware
mix atomcam2.install
```

### Remote update policy

The Atom Cam 2 boot layout does not currently support the standard Nerves remote `fwup` workflow safely.

A precheck callback was added to reject remote firmware updates and direct the developer to the supported installation task:

```text
Atom Cam 2 remote upload is disabled; use mix atomcam2.install
```

The generic message printed by Nerves after `mix firmware` still mentions `mix burn` and `mix upload`, but those commands are not the supported Atom Cam 2 update path.

## Control-kernel finding

The clean system build initially failed during post-image packaging:

```text
kernel image is too large for the AtomCam2 boot contract:
2207753 bytes (maximum 2031616)
```

The generated kernel configuration already contained:

```text
CONFIG_KERNEL_LZMA=y
CONFIG_CC_OPTIMIZE_FOR_SIZE=y
```

The previous and current generated system kernels were byte-identical:

```text
Size:   2207753 bytes
SHA256: f640cc4137de8a2c57443c371d1efca44ee884a3022123664479708f9d7d01ce
```

This proved that the ADR implementation had not increased the kernel size.

Inspection of the hardware-verified MicroSD card found a different kernel:

```text
Size:   1976325 bytes
SHA256: b50658eac32b57fdcb20383d82a54e6439acd7a3f7e9cb8b43edf4a4b89b03bc
```

The same file existed in:

```text
target/reference/atomcam-tools-release/extracted/factory_t31_ZMC6tiIDQN
target/atomcam2-control/factory_t31_ZMC6tiIDQN
target/recovery/known-good/factory_t31_ZMC6tiIDQN
target/atomcam2-sd/factory_t31_ZMC6tiIDQN
```

The working system intentionally uses a hybrid boot structure:

```text
Verified Atom Cam control kernel
+
Nerves-generated root filesystem
=
Atom Cam 2 MicroSD payload
```

The custom Nerves kernel is not yet the supported boot kernel.

The build already supported selecting the control kernel through:

```sh
export ATOMCAM2_KERNEL_IMAGE="$repo_root/target/atomcam2-control/factory_t31_ZMC6tiIDQN"
```

The release and post-image scripts were tightened so that:

- A control kernel is required
- Its SHA-256 is checked
- An unexpected kernel is rejected
- The oversized generated kernel cannot silently enter a released payload

This preserves the hardware-verified boot contract instead of weakening the size limit or removing kernel features without evidence.

## Release preparation

`scripts/release-artifacts.sh` was added to prepare:

- The custom Nerves toolchain artifact
- The Atom Cam 2 system artifact
- A `SHA256SUMS` file

It supports local creation, publication to a GitHub release, and isolated verification.

The release build also validates and injects the verified control kernel.

Publishing remains a system-maintenance operation and is not part of the regular example-application workflow.

## Smoke-check findings

The expanded smoke check initially inspected generated Buildroot content preserved under `tmp/`.

This caused two types of false positives:

- POSIX shell syntax checking was applied to an upstream Bash script using `extglob`
- Minimal-scope searches reported unrelated `rtsp`, `samba`, `webrtc`, and `rtmp` references from generated dependencies

The syntax scan was changed to exclude the repository `tmp/` directory. The temporary artifact backup was removed after the current artifact was verified.

The final smoke check completed with:

```text
ok: minimal ping/SSH scope looks clean
```

Generated build trees should not be treated as repository-owned source during static checks.

## Local build verification

The application was rebuilt with:

```sh
export MIX_TARGET=atomcam2
export MIX_ENV=prod
export ATOMCAM2_SYSTEM_SOURCE=local
export NERVES_TOOLCHAIN="$HOME/Projects/nerves/toolchains/o/nerves_toolchain_mipsel_nerves_linux_musl/x-tools/mipsel-nerves-linux-musl"
export ATOMCAM2_KERNEL_IMAGE="$repo_root/target/atomcam2-control/factory_t31_ZMC6tiIDQN"

mix deps.compile nerves_system_atomcam2 --force
mix firmware
```

The build completed successfully.

`vintage_net` and `vintage_net_wifi` compiled from clean dependency sources.

The control kernel and final application payload matched:

```text
SHA256: b50658eac32b57fdcb20383d82a54e6439acd7a3f7e9cb8b43edf4a4b89b03bc
Size:   1976325 bytes
```

The MicroSD installation task validated and installed:

```text
factory_t31_ZMC6tiIDQN
rootfs_hack.squashfs
hostname
authorized_keys
nerves-provisioning.conf
```

A timestamped backup was created before replacement.

## Hardware verification

The installed payload booted successfully.

`nerves.local` resolved to:

```text
192.168.10.117
```

Ping completed with no packet loss.

SSH opened the target IEx session:

```text
Interactive Elixir 1.20.2
Toolshed imported
```

The node name was:

```elixir
:"atomcam2_nerves_app@127.0.0.1"
```

The following applications were confirmed running:

```text
atomcam2_nerves_app
toolshed
vintage_net
vintage_net_wifi
mdns_lite
nerves_ssh
ssh_subsystem_fwup
nerves_runtime
nerves_uevent
nerves_logging
```

The `/data` path was accessible.

The SSH host key changed after installing the rebuilt firmware. Removing the stale `known_hosts` entry and accepting the new key was expected for this development device.

## Current status

The local ADR implementation is functionally complete:

- The application and system workflows are separated
- The system and toolchain have reusable artifact definitions
- Platform compatibility no longer mutates application dependencies
- The example application builds through a regular Nerves-style workflow
- The MicroSD installation task belongs to the system package
- The verified control kernel is enforced
- The resulting payload boots on hardware
- Wi-Fi, mDNS, ping, SSH, IEx, and Toolshed work

The ADR should not yet be marked fully implemented.

The remaining closure work is:

- Confirm that the SSH `fwup` subsystem rejects remote updates
- Commit the implementation
- Build and publish the `v0.1.0` toolchain and system artifacts
- Verify the release from an isolated clean checkout
- Build the example application without `ATOMCAM2_SYSTEM_SOURCE=local`
- Boot and verify a payload built from the published artifacts
- Record the final release evidence in ADR 0001

## Findings

- A successful local artifact build does not prove that the generated kernel is the hardware boot kernel.
- The currently supported system is a hybrid of a verified Atom Cam control kernel and a Nerves-generated root filesystem.
- Kernel-size limits should not be weakened until the bootloader contract is understood and verified.
- Platform-specific compatibility belongs in the system package, not in scripts that modify application dependencies.
- Build and scope checks must exclude generated trees to avoid upstream-source false positives.
- A reusable Nerves system requires both a published system artifact and a published toolchain artifact.
- Local hardware success is necessary but not sufficient to close the ADR; clean release consumption must also be verified.
