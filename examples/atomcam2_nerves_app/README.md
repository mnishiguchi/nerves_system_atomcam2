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

## Optional NAS recording export

ADR 0008 Phase 4 adds a small supervised SFTP exporter. It is inert when
`/data/atomcam2-vendor-camera/nas-export.conf` is absent or contains
`enabled=false`.

The enabled configuration is intentionally narrow:

```text
enabled=true
host=nas.local
port=22
user=atomcam2
user_dir=/data/atomcam2-vendor-camera/nas-ssh
remote_directory=recordings/atomcam2
poll_interval_seconds=60
retention_days=20
max_spool_bytes=536870912
```

Before first enablement, set `max_spool_bytes` above the existing local
backlog so the exporter can catch up without immediately shortening mobile
playback history. The cap is a target, not permission to discard unexported
footage.

`user_dir` must contain the NAS account's private key and a pre-provisioned
`known_hosts` file in the layout expected by OTP SSH. Password authentication
and automatic host-key acceptance are deliberately unsupported. Keep this
directory mode `0700` and its private files mode `0600`.

The exporter uploads only finalized paths shaped like
`YYYYMMDD/HH/MM.mp4`. It writes `MM.mp4.uploading` on the NAS and renames it
only after the byte count matches. Completed uploads are recorded under
`/data/atomcam2-vendor-camera/nas-exported`; the local MP4 remains available
for mobile playback until the configured spool cap removes the oldest
successfully exported file. Unexported files remain local even when that means
temporarily exceeding the cap. A local file becomes eligible for removal only
after the final remote name exists and its matching completion marker is
persistently recorded. Retries are idempotent when the final remote path already
has the expected size.

Inspect or trigger the supervised exporter from target IEx:

```elixir
Atomcam2NervesApp.NasExporter.status()
Atomcam2NervesApp.NasExporter.run_now()
```

The NAS account should be confined to `remote_directory`, since the exporter
also removes recording files in date directories older than
`retention_days`.

## Optional camera startup at boot

The vendor camera runtime remains disabled by default. After one successful
manual `prepare` and start/stop validation, opt in by creating:

```text
/data/atomcam2-vendor-camera/auto-start.conf
```

with exactly:

```text
enabled=true
```

The supervised boot integration waits for validated firmware, an Internet
connection, synchronized time, and a successful
`atomcam2-vendor-camera precheck`. It makes at most one automatic start attempt
per boot. A failed start or degraded runtime is reported without stopping
Nerves, rebooting the device, or attempting an automatic recovery loop.

Inspect or recheck it from target IEx:

```elixir
Atomcam2NervesApp.VendorCamera.status()
Atomcam2NervesApp.VendorCamera.run_now()
```

Set the file to `enabled=false` or remove it to disable startup on later boots.
Changing it does not stop a camera runtime that is already running.

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
