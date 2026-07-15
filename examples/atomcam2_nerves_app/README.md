# AtomCam2 minimal Nerves app

This app exists only to prove:

```sh
ping nerves.local
ssh nerves.local
```

It configures Wi-Fi through VintageNet, advertises `nerves.local` through `mdns_lite`, and starts NervesSSH.

Every `mix firmware` build preserves the merged application rootfs at:

```text
_build/<target>_<env>/nerves/images/rootfs_hack.final.squashfs
```

This is the final SquashFS after Nerves adds the application release under `/srv/erlang`. The build also creates the complete flat-SD payload at:

```text
_build/<target>_<env>/nerves/images/atomcam2-sd/
```

Do not install the smaller base system `rootfs.squashfs` or the system-build-only `target/atomcam2-sd` payload. Those do not contain the application release.

After a normal AtomCam2 production build, inspect the summary and install the final payload:

```sh
cat _build/atomcam2_prod/nerves/images/rootfs_hack.final.squashfs.summary.txt

../../scripts/install-sd-files.sh \
  --mount /path/to/mounted/sd \
  --dry-run

../../scripts/install-sd-files.sh \
  --mount /path/to/mounted/sd \
  --force
```
