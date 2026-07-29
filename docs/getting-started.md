# Getting started

This guide takes a source checkout through the first MicroSD installation,
network check, and optional mobile-app camera startup.

For the system design and safety boundaries, see the
[Architecture overview](architecture.md). For all example-application options,
see its [README](../examples/atomcam2_nerves_app/README.md).

## Before you begin

You need:

- an Atom Cam 2 and a MicroSD card;
- a working Nerves development environment with `elixir`, `mix`, and `fwup`;
- Wi-Fi credentials; and
- at least one SSH public key under `~/.ssh`.

The complete installation erases the selected MicroSD card. Verify the device
path shown by fwup before confirming the write.

Application developers consume the tagged system source and its prebuilt system
and custom toolchain artifacts from the matching GitHub release. Building the
system or toolchain locally is not required for this workflow.

## 1. Build and install

Start from the repository root, enter the example application, and configure
the target and Wi-Fi:

```sh
cd examples/atomcam2_nerves_app

export MIX_TARGET=atomcam2
export MIX_ENV=prod
export NERVES_WIFI_SSID=your-ssid
export NERVES_WIFI_PASSPHRASE=your-passphrase

mix setup
mix firmware.burn
```

`mix setup` only retrieves dependencies. Target compatibility is supplied by
the released system artifact; application dependency source is not modified.

`mix firmware.burn` builds the firmware and writes it through the fwup
`complete` task. Select the MicroSD device when fwup prompts, power off the
camera, insert the card, and power it on.

The build includes public keys found under `~/.ssh/*.pub`. A specific key file
can instead be selected through the example application's
[local environment](../examples/atomcam2_nerves_app/README.md#local-development-environment).

After running `mix firmware`, use `mix burn` to write the existing firmware
bundle without rebuilding it.

## 2. Confirm the core system

Allow time for the camera to boot and join Wi-Fi, then run:

```sh
ping nerves.local
ssh nerves@nerves.local
```

The SSH session opens target IEx. At this point the core Nerves platform is
working; camera compatibility and NAS export are still optional.

## 3. Try the standard mobile application

This step assumes the device is already paired with the standard Atom mobile
application.

From target IEx, prepare the private compatibility state once and start the
vendor runtime:

```elixir
cmd("atomcam2-vendor-camera precheck")
cmd("atomcam2-vendor-camera prepare")
cmd("atomcam2-vendor-camera start")
cmd("atomcam2-vendor-camera status")
```

`status` should report `result=running`. Test live view and recording playback
in the mobile application.

To stop the optional runtime:

```elixir
cmd("atomcam2-vendor-camera stop")
```

The protected kernel keeps the loaded camera modules resident, so a deliberate
reboot is required before another start after a stop.

Once manual operation is proven, see
[Optional camera startup at boot](../examples/atomcam2_nerves_app/README.md#optional-camera-startup-at-boot).

## 4. Continue from a working baseline

- Use the [remote firmware update](#remote-firmware-updates) workflow for later
  application firmware.
- Configure the
  [optional SFTP exporter](../examples/atomcam2_nerves_app/README.md#optional-nas-recording-export)
  only after the core system and mobile live view are healthy.
- Read the [Architecture overview](architecture.md) before changing the boot,
  storage, update, watchdog, or vendor-runtime boundaries.

## Remote firmware updates

The first installation must use removable media. After the device is running
firmware with A/B update support, build subsequent application firmware on the
host:

```sh
mix firmware
```

When the optional vendor camera compatibility runtime is enabled, stop it from
target IEx before uploading. Connect with:

```sh
ssh nerves@nerves.local
```

Then stop it and leave IEx:

```elixir
cmd("atomcam2-vendor-camera stop")
exit()
```

Upload from the host:

```sh
mix upload nerves.local
```

The successful upload writes the inactive application slot and reboots. The
persistent opt-in configuration starts the vendor runtime again after the new
firmware is validated and its readiness checks pass.

The updater stages the firmware under `/data`, checks its platform and
architecture, writes and verifies only the inactive application slot, and then
records that slot as pending. An interrupted transfer removes its staged file
and does not reboot the device.

SSH public-key authentication controls access to the update endpoint. Fwup
validates archive and resource integrity. Mandatory firmware signing is not
part of the baseline workflow, matching ordinary Nerves systems; see
[ADR 0007](adr/0007-require-signed-firmware-for-device-side-updates.md).

The candidate is confirmed only after its local health checks pass. Until then,
the previous confirmed slot remains the rollback target. Remote updates do not
rewrite the FAT boot partition, protected control kernel, boot manager, active
application slot, or persistent data partition.

Happy-path OTA and `Nerves.Runtime.revert/0` testing has passed on physical
hardware. Power-interruption, crash-loop, and the remaining physical failure
matrix are still required before treating remote updates as production-ready.
