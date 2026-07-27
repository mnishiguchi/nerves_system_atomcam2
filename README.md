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

An optional manual vendor-camera compatibility runtime is available for
supervised testing. It remains disabled by default and keeps Nerves in control
of boot, networking, the hardware watchdog, updates, and recovery. Automatic
camera startup, NAS export, retention, RTSP, WebUI, Samba, and internal flash
writes are not enabled. Vendor network, cloud, mobile live view, recorded
playback, SD health, and continuous one-minute local recording are physically
verified. Remote firmware updates remain experimental until the physical OTA
validation matrix is complete.

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

ADR 0008 defines a second, optional boundary for camera compatibility. It reads
the vendor camera binaries, libraries, drivers, and protected configuration
already exposed below `/atom`, while keeping Nerves in control of boot,
networking, the hardware watchdog, updates, and recovery. It does not adopt the
complete `atomcam_tools` runtime.

The target command supports a read-only precheck and a deliberately manual
runtime:

```sh
atomcam2-vendor-camera precheck
atomcam2-vendor-camera prepare
atomcam2-vendor-camera start
atomcam2-vendor-camera status
atomcam2-vendor-camera stop
```

`precheck` verifies the live vendor mounts, required files, module ABI, reserved
memory, `/data`, IPC, Wi-Fi, watchdog ownership, and NAS filesystem
capabilities. `prepare` makes a mode-private copy of protected vendor
configuration below `/data` without printing its contents. `start` loads only
the required camera modules and starts `assis`, `hl_client`, and `iCamera_app`
in the isolated compatibility layout. A narrow preload shim keeps the hardware
watchdog and raw MicroSD under Nerves ownership. `stop` removes the vendor
process tree, mounts, and IPC. The protected
kernel marks the camera modules permanent, so a reboot is required before
another start.

The corrected manual runtime has passed physical network, cloud, mobile live
view, recorded playback, SD health, one-minute continuous recording,
start/status/stop/reboot, SSH, Wi-Fi, watchdog ownership, and firmware
validation checks. Automatic camera boot remains unimplemented.

Phase 4 now has an opt-in NAS exporter in the example application. The fixed
protected kernel does not provide NFS or CIFS, so the exporter uses the OTP
SFTP client already shipped for Nerves SSH support. It requires a dedicated
key-based NAS account and a pre-provisioned host key, publishes completed
segments through a temporary name and atomic rename, retries without
duplicating equal-size remote files, bounds the local playback spool, and
removes dated NAS recordings after the configured retention period. It remains
disabled without persistent `/data` configuration and still requires a
production-NAS and sustained spool-pressure acceptance run. A physical
device-to-disposable-SFTP trial already passes upload, checksum, atomic
publication, idempotent retry, selective retention, and connection recovery.

The architecture and physical evidence are recorded in
[`ADR 0008`](docs/adr/0008-run-vendor-camera-runtime-as-optional-compatibility-service.md)
and the
[`manual-runtime worklog`](docs/worklog/20260726-adr-0008-vendor-camera-manual-runtime.md).
The corrected mobile/storage investigation is in the
[`mobile/storage worklog`](docs/worklog/20260726-adr-0008-mobile-and-storage-compatibility.md).

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
