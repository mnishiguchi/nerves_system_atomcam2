# AtomCam2 minimal Nerves app

This app proves the supported Atom Cam 2 application workflow.

Perform the initial installation through removable media:

```sh
mix setup
mix firmware.burn
```

After the device is running firmware with ADR 0006 update support, subsequent
application firmware can be installed remotely:

```sh
mix firmware
mix upload nerves.local
```

It configures Wi-Fi through VintageNet, advertises `nerves.local` through
`mdns_lite`, starts NervesSSH, and imports Toolshed in target IEx sessions.

## System dependency

The default dependency uses the tagged `nerves_system_atomcam2` source and
retrieves its prebuilt system and custom toolchain artifacts from the matching
GitHub release:

```sh
mix setup
```

## Local development environment

System maintainers can build against the current repository checkout through the
tracked direnv example:

```sh
cp .envrc.example .envrc
direnv allow
```

The real `.envrc` is ignored because it may contain machine-specific paths, SSH
keys, and Wi-Fi credentials. Review the copied file before building.

The important variables are:

- `ATOMCAM2_SYSTEM_SOURCE=local` selects the system from the current repository.
- `ATOMCAM2_KERNEL_IMAGE` points to the verified Atom Cam 2 control kernel.
- `NERVES_TOOLCHAIN` selects the validated custom compiler when it is not
  already configured.
- `ATOMCAM2_AUTHORIZED_KEYS`, `NERVES_WIFI_SSID`, and
  `NERVES_WIFI_PASSPHRASE` are optional local settings.

The normal local workflow remains:

```sh
mix setup
mix firmware.burn
```

Unset `ATOMCAM2_SYSTEM_SOURCE` when explicitly validating a published system
artifact instead of the current checkout.

The Linux 3.10 compatibility definition required by VintageNet is supplied by
the Nerves system staging headers. The application no longer modifies dependency
source code during setup.

## Build and install

Build and write firmware:

```sh
mix firmware.burn
```

To write an existing firmware bundle:

```sh
mix firmware
mix burn
```

Both workflows use the fwup `complete` task by default. Pass `--device` to
select specific media.

`mix atomcam2.install` remains only as a deprecated compatibility wrapper around `mix burn`.

## Target IEx

```sh
ssh nerves@nerves.local
```

Toolshed is imported automatically through `/etc/iex.exs`, so helpers such as
`tree`, `top`, and `exit` are immediately available.

## Remote updates

After the initial complete installation, standard Nerves firmware uploads are
supported:

```sh
mix firmware
mix upload nerves.local
```

The SSH firmware subsystem forwards the uploaded bundle to the Atom Cam 2
updater. The updater stages the bundle under `/data`, validates the target
platform and architecture, selects the inactive application slot, writes and
verifies the root filesystem, and records the candidate as pending.

SSH public-key authentication authorizes access to the update endpoint. Fwup
validates archive and resource integrity. Firmware publisher signatures are
optional, as they are for the ordinary Nerves workflow, and are not required by
this application. See
[`ADR 0007`](../../docs/adr/0007-require-signed-firmware-for-device-side-updates.md).

The upload reports `receiving`, the received byte count, `installing`, fwup
write progress, and the updater's final status. If a transfer ends before SSH
EOF, the staged file is removed and the device is not rebooted.

A successful upload reboots the device. After the candidate reaches the
application root and passes its local health checks, it is confirmed through
`Nerves.Runtime.validate_firmware/0`. Until confirmation, the previous slot
remains the rollback target.

The upload path does not rewrite the FAT boot partition, protected control
kernel, boot manager, active application slot, or persistent data partition.
The first firmware containing this support must therefore be installed with
`mix firmware.burn`.

Every firmware build preserves the merged application rootfs at:

```text
_build/<target>_<env>/nerves/images/rootfs_hack.final.squashfs
```

The complete flat-SD payload is generated at:

```text
_build/<target>_<env>/nerves/images/atomcam2-sd/
```
