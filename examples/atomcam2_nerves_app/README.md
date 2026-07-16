# AtomCam2 minimal Nerves app

This app exists only to prove:

```sh
ping nerves.local
ssh nerves@nerves.local
```

It configures Wi-Fi through VintageNet, advertises `nerves.local` through `mdns_lite`, and starts NervesSSH.

## Build

Prepare dependencies and apply the Atom Cam 2 Linux 3.10 compatibility patch:

```sh
mix setup
```

The setup alias is idempotent. Run it again after cleaning or replacing `deps/vintage_net`.

Build the firmware:

```sh
mix firmware
```

## Target IEx

The target imports Toolshed automatically through `/etc/iex.exs`. Standard Nerves shell helpers are available immediately after connecting:

```sh
ssh nerves@nerves.local
```

```elixir
exit
```

Every `mix firmware` build preserves the merged application rootfs at:

```text
_build/<target>_<env>/nerves/images/rootfs_hack.final.squashfs
```

This is the final SquashFS after Nerves adds the application release under `/srv/erlang`. The build also creates the complete flat-SD payload at:

```text
_build/<target>_<env>/nerves/images/atomcam2-sd/
```

Do not install the smaller base system `rootfs.squashfs` or the system-build-only `target/atomcam2-sd` payload. Those do not contain the application release.

After a normal Atom Cam 2 production build, inspect the summary and install the final payload:

```sh
cat _build/atomcam2_prod/nerves/images/rootfs_hack.final.squashfs.summary.txt

mix atomcam2.install --dry-run
mix atomcam2.install
```

The task detects a mounted filesystem labeled `ATOMCAM2`. Pass an explicit path when needed:

```sh
mix atomcam2.install --mount /path/to/mounted/sd
```

It delegates payload validation, backup, installation verification, and write synchronization to `scripts/install-sd-files.sh`.
