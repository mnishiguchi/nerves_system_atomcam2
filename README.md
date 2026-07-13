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

This archive is a full source snapshot for the minimal bring-up direction. It does not include compiled artifacts, proprietary vendor files, or a proven hardware-specific kernel configuration. Treat the kernel and Wi-Fi driver details as the next hardware-confirmation layer.

The safe first boot contract is the flat AtomCam2 microSD payload. The first four files match the AtomCam2 boot handoff; `nerves-provisioning.conf` is for the Nerves app after rootfs handoff:

```text
factory_t31_ZMC6tiIDQN
rootfs_hack.squashfs
hostname
authorized_keys
nerves-provisioning.conf
```

Target-side helper scripts are installed through `rootfs_overlay` only. The `package/` directory is kept as a placeholder for future compiled Buildroot packages, not for duplicating plain shell helpers.

## Build shape

The intended flow is:

```sh
./scripts/check-prereqs.sh
./scripts/smoke-check.sh
./scripts/build-firmware-log.sh
```

Host-side logs are written under `tmp/log/` by default.

For the first Wi-Fi/SSH image, pass credentials and the public key through the
build environment:

```sh
NERVES_WIFI_SSID="your-ssid" \
NERVES_WIFI_PASSPHRASE="your-passphrase" \
ATOMCAM2_AUTHORIZED_KEYS="$HOME/.ssh/id_ed25519.pub" \
./scripts/build-firmware-log.sh
```

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
5. If it fails, power down and inspect the FAT partition reports. The helper below copies the breadcrumbs into `target/atomcam2-boot-reports/`:

```sh
./scripts/collect-boot-report.sh --mount /path/to/mounted/sd
```

The copied report files stay under `target/atomcam2-boot-reports/`, and the host-side collection log is written to `tmp/log/`.

Expected report files:

```text
atomcam2-init-entered.env
atomcam2-initramfs.env
atomcam2-pre-run.env
atomcam2-network.env
```
