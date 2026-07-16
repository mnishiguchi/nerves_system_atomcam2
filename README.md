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

Camera runtime, RTSP, WebUI, Samba, vendor application compatibility, internal flash writes, and production updates remain out of scope.

## Quick start

This repository is still in the system-porting stage. A fresh checkout currently needs one-time system preparation before the repeated application build loop becomes simple.

### 1. Configure local values

Configure the ignored local environment file:

```text
examples/atomcam2_nerves_app/.envrc
```

It should provide:

```sh
export NERVES_TOOLCHAIN=/absolute/path/to/x-tools/mipsel-nerves-linux-musl
export NERVES_WIFI_SSID=your-ssid
export NERVES_WIFI_PASSPHRASE=your-passphrase
export ATOMCAM2_AUTHORIZED_KEYS=/absolute/path/to/authorized_keys
```

Load it:

```sh
cd examples/atomcam2_nerves_app
direnv allow
```

### 2. Prepare the system inputs once

From the repository root:

```sh
./scripts/prepare-toolchain-archive.sh
./scripts/check-prereqs.sh
./scripts/smoke-check.sh
```

The toolchain preparation script creates:

```text
target/toolchains/atomcam2-mips32r2-nerves-toolchain.tar.xz
```

It leaves an existing non-empty archive unchanged. Pass `--force` to regenerate it from the current `NERVES_TOOLCHAIN` directory.

### 3. Set up application dependencies

From the example application:

```sh
cd examples/atomcam2_nerves_app
mix setup
```

The setup alias runs `mix deps.get` and applies the required VintageNet compatibility patch for the Linux 3.10 headers used by Atom Cam 2. It is idempotent and should be run again after cleaning or replacing `deps/vintage_net`.

### 4. Build the firmware

```sh
mix firmware
```

For a logged maintainer build that also reruns repository checks:

```sh
../../scripts/build-firmware-log.sh
```

### 5. Install the flat-SD payload

The installable payload is:

```text
_build/atomcam2_prod/nerves/images/atomcam2-sd/
```

Install it to the mounted Atom Cam 2 MicroSD FAT partition:

```sh
../../scripts/install-sd-files.sh \
  --mount /path/to/mounted/sd \
  --dry-run

../../scripts/install-sd-files.sh \
  --mount /path/to/mounted/sd \
  --force
```

The installer validates the payload and backs up the current files before replacement.

After power-cycling the camera:

```sh
ping nerves.local
ssh nerves@nerves.local
```

## Intended application workflow

The repeated dependency and firmware build loop is now:

```sh
mix setup
mix firmware
```

The remaining installation goal is a dedicated command:

```sh
mix atomcam2.install
```

Until that task exists, use `scripts/install-sd-files.sh` as shown above. Later application updates should use `mix upload` when a safe update path is available.

Application developers should not need to build Buildroot, prepare a toolchain archive, patch VintageNet manually, or understand the vendor boot chain. Those responsibilities belong to the system-maintainer workflow and should be delivered through a reusable prebuilt `nerves_system_atomcam2` artifact.

The architectural decision and transition plan are recorded in [`docs/adr/0001-separate-application-workflow-from-system-maintenance.md`](docs/adr/0001-separate-application-workflow-from-system-maintenance.md).

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

Buildroot consumes the generated archive through `nerves_defconfig`. The example application uses `NERVES_TOOLCHAIN` for ERTS, ports, NIFs, and other native dependencies.

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

## System-maintainer workflow

System maintainers are responsible for:

- Building and validating the custom MIPS32R2 toolchain.
- Preparing the Buildroot toolchain archive.
- Building Buildroot, Linux, BusyBox, and the initramfs.
- Preserving the vendor Linux 3.10 boot contract.
- Maintaining the vendor SDIO Wi-Fi driver integration.
- Maintaining or upstreaming the VintageNet Linux 3.10 compatibility change.
- Producing and publishing a reusable system artifact.
- Preserving a known-good recovery payload before hardware experiments.

Run the static checks before a clean system build:

```sh
./scripts/check-prereqs.sh
./scripts/smoke-check.sh
./scripts/atomcam2-check-minimal-ssh-scope.sh .
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
