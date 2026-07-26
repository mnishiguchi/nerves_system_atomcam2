# nerves_system_atomcam2

Experimental Nerves system for Atom Cam 2.

## Current status

The first hardware milestone is verified from a clean source build:

```text
Atom Cam 2 boots from MicroSD
-> initramfs mounts rootfs_hack.squashfs
-> erlinit starts the Nerves release
-> the vendor SDIO Wi-Fi driver exposes wlan0
-> VintageNet joins Wi-Fi
-> mdns_lite advertises nerves.local
-> NervesSSH accepts SSH
```

The verified host commands are:

```sh
ping nerves.local
ssh nerves@nerves.local
```

The verified IEx node is:

```elixir
:"atomcam2_nerves_app@127.0.0.1"
```

Commit `3cd22ab` is the reproducible ping and SSH baseline. It uses the explicit minimal runtime stack without `nerves_pack` or `nerves_motd`.

Camera runtime, RTSP, WebUI, Samba, vendor application compatibility, and internal flash writes remain out of scope. Remote firmware updates remain experimental until the physical OTA validation matrix is complete.

## Application workflow

Application developers consume the tagged system source and its prebuilt system
and custom toolchain artifacts from the matching GitHub release.

Configure Wi-Fi credentials before building:

```sh
export NERVES_WIFI_SSID=your-ssid
export NERVES_WIFI_PASSPHRASE=your-passphrase
```

Then run from the example application:

```sh
cd examples/atomcam2_nerves_app
export MIX_TARGET=atomcam2
export MIX_ENV=prod

mix setup
mix firmware.burn
```

`mix setup` only retrieves dependencies. Target compatibility is supplied by the
system artifact; application dependency source is not modified.

`mix firmware.burn` builds the firmware and writes it through the fwup
`complete` task. After running `mix firmware`, use `mix burn` to write the
existing firmware bundle without rebuilding it.

## Remote firmware updates

The ADR 0006 A/B layout supports standard `mix upload` after the device is
running firmware that includes the safe updater.

The first installation must still use removable media:

    mix firmware.burn

Subsequent application firmware can be uploaded over SSH:

    mix firmware
    mix upload nerves.local

The device stages the firmware under `/data`, validates its platform and
architecture, selects the inactive application slot, writes only that slot,
verifies the written root filesystem, and records it as pending. The SSH
subsystem then reboots the device.

SSH public-key authentication authorizes access to the update endpoint. Fwup
validates archive and resource integrity; the Atom Cam 2 updater adds the
platform, architecture, inactive-slot, and written-rootfs checks required by its
custom media layout. Mandatory firmware signing is deliberately not part of the
baseline workflow, matching the ordinary Nerves system model. The rationale is
recorded in
[`ADR 0007`](docs/adr/0007-require-signed-firmware-for-device-side-updates.md).

The upload reports its receiving and installation phases, received byte count,
fwup write progress, and final updater status. An interrupted transfer removes
its staged file and does not reboot the device.

After the pending firmware boots, the application waits for local services and
the persistent data filesystem to become healthy before confirming the new
slot. The previous confirmed slot remains available for rollback.

Remote updates do not rewrite the FAT boot partition, protected control kernel,
boot manager, active application slot, or persistent data partition. Physical
happy-path OTA and `Nerves.Runtime.revert/0` testing has passed on an Atom Cam 2.
Power-interruption, crash-loop, and the remaining physical failure matrix are
still required before treating this path as production-ready.

## System-maintainer workflow

System maintainers can opt into local system compilation:

```sh
export ATOMCAM2_SYSTEM_SOURCE=local
export NERVES_TOOLCHAIN=/absolute/path/to/x-tools/mipsel-nerves-linux-musl

./scripts/prepare-toolchain-archive.sh
./scripts/check-prereqs.sh
./scripts/smoke-check.sh

cd examples/atomcam2_nerves_app
mix setup
mix firmware
```

The custom compiler must target MIPS32R2 soft-float without DSP ASE. Buildroot
consumes its prepared archive, while Nerves uses the same compiler for ERTS,
ports, NIFs, and other target-native dependencies.

The system installs `atomcam2-linux-3.10-compat.h` into its staging sysroot and
adds it to target compiler flags. This supplies the `IFA_FLAGS` definition needed
by VintageNet without patching `deps/vintage_net`.

## Releasing artifacts

Prepare each release in a focused pull request that:

- bumps `VERSION`, `toolchain/VERSION`, and the example application's system
  dependency version;
- bumps the example application version when its firmware changes;
- moves the completed changes into a dated `CHANGELOG.md` section; and
- keeps the release tag, system, toolchain, and example system dependency
  aligned.

After that pull request is merged, fast-forward a clean `main` checkout and
publish the matching tag, GitHub Release, system artifact, toolchain artifact,
and checksum manifest:

```sh
git switch main
git pull --ff-only
./scripts/release-artifacts.sh --publish
```

The script derives the tag from `VERSION` and uses GitHub-generated release
notes. Run it without flags to build the artifacts locally without publishing.

After publication, prove that an isolated checkout of the tag downloads both
artifacts and builds without `NERVES_SYSTEM`, `NERVES_TOOLCHAIN`, or a local
system override:

```sh
./scripts/release-artifacts.sh --verify
```

The release tag, system package version, toolchain package version, and example
application system version must remain aligned.

The architectural decision is recorded in
[`docs/adr/0001-separate-application-workflow-from-system-maintenance.md`](docs/adr/0001-separate-application-workflow-from-system-maintenance.md).

## Atom Cam 2 boot contract

The supported first-boot path is a flat MicroSD payload:

```text
factory_t31_ZMC6tiIDQN
rootfs_hack.squashfs
hostname
authorized_keys
nerves-provisioning.conf
```

The first four files participate in the Atom Cam 2 boot handoff. `nerves-provisioning.conf` is consumed by the Nerves application after rootfs handoff.

## Relationship to atomcam_tools

This project began by using [`mnakada/atomcam_tools`](https://github.com/mnakada/atomcam_tools) as a hardware reference. The supported system no longer uses its root filesystem, application services, or on-device update flow.

The remaining direct dependencies are deliberately narrow:

- the verified `factory_t31_ZMC6tiIDQN` control kernel, including its active vendor initramfs
- the matching `atbm603x_wifi_sdio.ko` Wi-Fi module

The project also retains adapted hardware conventions from `atomcam_tools`:

- the `factory_t31_ZMC6tiIDQN` and `rootfs_hack.squashfs` boot filenames
- the loop-mounted SquashFS and `switch_root` handoff
- the vendor kernel configuration as a baseline for future custom-kernel work

Apart from the retained Wi-Fi module, everything after the root filesystem handoff is owned by this project: the Nerves root filesystem, Elixir application, custom Nerves toolchain, VintageNet provisioning, SSH runtime, fwup media workflows, and safety checks. The supported firmware is therefore intentionally hybrid:

```text
verified Atom Cam 2 control kernel
+
Nerves-generated root filesystem and application
```

The application build preserves the final merged SquashFS at:

```text
examples/atomcam2_nerves_app/_build/atomcam2_prod/nerves/images/rootfs_hack.final.squashfs
```

This is the final rootfs after Nerves adds the Erlang release under `/srv/erlang`. Do not install the smaller base-system `rootfs.squashfs` or `target/atomcam2-sd/`; they do not contain the application release.

Inspect the generated summary with:

```sh
cat examples/atomcam2_nerves_app/_build/atomcam2_prod/nerves/images/rootfs_hack.final.squashfs.summary.txt
```

## Custom toolchain

Atom Cam 2 requires a MIPS32R2 soft-float toolchain without DSP ASE. The stock Nerves MIPSEL toolchain targets `24kec`, whose musl runtime enables instructions that raise `SIGILL` on the Ingenic T31.

Build the replacement toolchain from a checkout of [`nerves-project/toolchains`](https://github.com/nerves-project/toolchains), then point `NERVES_TOOLCHAIN` at the unpacked toolchain:

```sh
export NERVES_TOOLCHAIN=/absolute/path/to/x-tools/mipsel-nerves-linux-musl
./scripts/prepare-toolchain-archive.sh
```

Buildroot consumes the generated archive through `nerves_defconfig`. Released application builds download the matching custom toolchain artifact automatically; `NERVES_TOOLCHAIN` is only required for system maintenance and release creation.

For the investigation that established this requirement, see [`docs/worklog/20260713-atomcam2-toolchain-dsp-ase-investigation.md`](docs/worklog/20260713-atomcam2-toolchain-dsp-ase-investigation.md).

## Wi-Fi provisioning

The example application configures `wlan0` through VintageNet. Credential priority is:

1. `/media/mmc/nerves-provisioning.conf`
2. environment variables embedded into the release build
3. `/media/mmc/wpa_supplicant.conf`

The packaging helper reuses an existing generated `nerves-provisioning.conf` from the images directory when present.

The preferred first test is explicit provisioning. The packaged file can also be edited before installation:

```sh
cat > _build/atomcam2_prod/nerves/images/atomcam2-sd/nerves-provisioning.conf <<'EOF_PROVISIONING'
NERVES_WIFI_SSID=your-ssid
NERVES_WIFI_PASSPHRASE=your-passphrase
EOF_PROVISIONING
```

## Recovery and diagnostics

When a firmware experiment breaks networking, restore the most recent known-good payload before investigating further.

For boot failures, power down the camera, mount the MicroSD card, and collect the FAT-partition breadcrumbs:

```sh
./scripts/collect-boot-report.sh --mount /path/to/mounted/sd
```

Reports are copied to:

```text
target/atomcam2-boot-reports/
```

The confirmed first network milestone and resolved blockers are documented in [`docs/worklog/20260715-atomcam2-ping-ssh-bringup.md`](docs/worklog/20260715-atomcam2-ping-ssh-bringup.md).
