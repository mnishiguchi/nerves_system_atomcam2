# AtomCam2 minimal Nerves app

This app proves the supported Atom Cam 2 application workflow:

```sh
mix setup
mix firmware.burn
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

`mix upload` is intentionally unsupported. The running system mounts the same
FAT partition that contains the vendor kernel and SquashFS files, and an in-place
fwup update has not been proven safe. The target rejects connections to the fwup
SSH subsystem. Power down the camera and use `mix firmware.burn`, or `mix burn`
when the firmware is already built.

Every firmware build preserves the merged application rootfs at:

```text
_build/<target>_<env>/nerves/images/rootfs_hack.final.squashfs
```

The complete flat-SD payload is generated at:

```text
_build/<target>_<env>/nerves/images/atomcam2-sd/
```
