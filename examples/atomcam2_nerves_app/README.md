# AtomCam2 minimal Nerves app

This app proves the supported Atom Cam 2 application workflow:

```sh
mix setup
mix firmware
mix atomcam2.install
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

System maintainers can compile the local checkout explicitly:

```sh
export ATOMCAM2_SYSTEM_SOURCE=local
mix setup
mix firmware
```

Local system compilation also requires the validated custom compiler through
`NERVES_TOOLCHAIN` and the Buildroot toolchain archive prepared by the repository
maintainer scripts.

The Linux 3.10 compatibility definition required by VintageNet is supplied by
the Nerves system staging headers. The application no longer modifies dependency
source code during setup.

## Build and install

```sh
mix firmware
mix atomcam2.install --dry-run
mix atomcam2.install
```

The install task detects a mounted filesystem labeled `ATOMCAM2`. Pass an
explicit path when needed:

```sh
mix atomcam2.install --mount /path/to/mounted/sd
```

It delegates payload validation, backup, installation verification, and write
synchronization to the installer shipped by the `nerves_system_atomcam2` dependency.

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
SSH subsystem. Power down the camera and use `mix atomcam2.install` instead.

Every firmware build preserves the merged application rootfs at:

```text
_build/<target>_<env>/nerves/images/rootfs_hack.final.squashfs
```

The complete flat-SD payload is generated at:

```text
_build/<target>_<env>/nerves/images/atomcam2-sd/
```
