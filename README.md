# nerves_system_atomcam2

Experimental minimal Nerves system source tree for AtomCam2.

## Current MVP

The first milestone is deliberately narrow:

```text
AtomCam2 boots from microSD
-> initramfs mounts rootfs_hack.squashfs
-> erlinit starts the Nerves release
-> AtomCam2 Wi-Fi is made visible as wlan0
-> VintageNet joins Wi-Fi
-> mdns_lite advertises nerves.local
-> NervesSSH accepts SSH
```

Target commands from the host:

```sh
ping nerves.local
ssh nerves.local
```

Camera runtime, RTSP, WebUI, Samba, vendor app compatibility, and internal flash writes are intentionally out of scope.

## Important status

The SD boot path, root filesystem handoff, and MIPS32R2 soft-float dynamic userspace have been proven on Atom Cam 2. The stock Nerves MIPSEL toolchain is not usable for this target because its `24kec` profile enables DSP ASE instructions that raise `SIGILL` on the Ingenic T31.

A locally built MIPS32R2 soft-float toolchain without DSP ASE has passed both PIE and non-PIE dynamic probes. The next checkpoint is a fully clean Nerves firmware build with that same toolchain used by Buildroot, ERTS, ports, NIFs, and native dependencies. The custom Nerves kernel path also remains unproven.

The safe first boot contract is the flat AtomCam2 microSD payload. The first four files match the AtomCam2 boot handoff; `nerves-provisioning.conf` is for the Nerves app after rootfs handoff:

```text
factory_t31_ZMC6tiIDQN
rootfs_hack.squashfs
hostname
authorized_keys
nerves-provisioning.conf
```

Target-side helper scripts are installed through `rootfs_overlay` only. The `package/` directory is kept as a placeholder for future compiled Buildroot packages, not for duplicating plain shell helpers.

## Custom toolchain

Atom Cam 2 requires a MIPS32R2 soft-float toolchain without DSP ASE. The stock Nerves MIPSEL toolchain still targets `24kec`, so its musl runtime is not usable on the Ingenic T31.

Build that replacement toolchain from a checkout of [`nerves-project/toolchains`](https://github.com/nerves-project/toolchains). This repo does not yet automate generating, unpacking, or validating the archive, so stage it in the two forms expected by the current build:

```text
target/toolchains/atomcam2-mips32r2-nerves-toolchain.tar.xz
examples/atomcam2_nerves_app/.envrc -> export NERVES_TOOLCHAIN=/absolute/path/to/x-tools/mipsel-nerves-linux-musl
```

The archive is consumed by Buildroot through `nerves_defconfig`. `NERVES_TOOLCHAIN` is used by the example app build for ERTS, ports, NIFs, and other native dependencies.

For the investigation that led to this requirement, see `docs/worklog/20260713-atomcam2-toolchain-dsp-ase-investigation.md`.

## Build shape

Configure the local development environment in:

```text
examples/atomcam2_nerves_app/.envrc
```

This file contains the custom toolchain path, Wi-Fi credentials, authorized key path, and local build settings.

Then build from the example app:

```sh
cd examples/atomcam2_nerves_app
direnv allow
mix deps.get
../../scripts/patch-vintage-net-linux-3.10.sh
../../scripts/build-firmware-log.sh
```

The build helper writes logs to `tmp/log/`, reruns the prerequisite and smoke checks, and then runs `mix deps.get` plus `mix firmware`.

The VintageNet compatibility patch is still a manual step because it modifies `deps/vintage_net` after `mix deps.get`.

Then package the generated Buildroot images for AtomCam2 flat-SD testing:

```sh
cd ../..
./scripts/atomcam2-package-flat-sd.sh \
  --images-dir .nerves/artifacts/nerves_system_atomcam2-portable-0.1.0/images \
  --output-dir target/atomcam2-sd \
  --hostname nerves \
  --authorized-keys "$HOME/.ssh/id_ed25519.pub"

./scripts/atomcam2-check-sd-payload.sh target/atomcam2-sd
```

Copy the contents of `target/atomcam2-sd/` to the AtomCam2 microSD FAT partition, or use the helper. The helper refuses obvious dangerous paths, such as using the same directory for the source and mounted SD partition:

```sh
./scripts/install-sd-files.sh \
  --source target/atomcam2-sd \
  --mount /path/to/mounted/sd \
  --dry-run

./scripts/install-sd-files.sh \
  --source target/atomcam2-sd \
  --mount /path/to/mounted/sd \
  --force
```

## Wi-Fi model

The example app configures `wlan0` through VintageNet. Credential priority is:

1. `/media/mmc/nerves-provisioning.conf`
2. environment variables embedded into the release build
3. `/media/mmc/wpa_supplicant.conf`

The packaging helper reuses an existing generated `nerves-provisioning.conf` from the images directory when present.

The preferred first test is explicit provisioning. It is also safe to edit the packaged file directly before copying it to the SD card:

```sh
cat > target/atomcam2-sd/nerves-provisioning.conf <<'EOF_PROVISIONING'
NERVES_WIFI_SSID=your-ssid
NERVES_WIFI_PASSPHRASE=your-passphrase
EOF_PROVISIONING
```

## Smoke checks

```sh
./scripts/smoke-check.sh
./scripts/atomcam2-check-minimal-ssh-scope.sh .
```

## Next hardware loop

1. Boot once with the microSD card.
2. Wait 1-2 minutes.
3. Try `ping nerves.local`.
4. Try `ssh nerves.local`.
5. If it fails, power down and inspect the FAT partition reports. The helper below copies the breadcrumbs into `target/atomcam2-boot-reports/` and writes the host collection log to `tmp/log/`:

```sh
./scripts/collect-boot-report.sh --mount /path/to/mounted/sd
```

Expected report files:

```text
atomcam2-init-entered.env
atomcam2-initramfs.env
atomcam2-pre-run.env
atomcam2-wifi-driver.env
atomcam2-network.env
```
