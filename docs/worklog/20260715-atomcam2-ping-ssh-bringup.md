# 20260715 AtomCam2 Nerves ping and SSH bring-up

## Result

On July 15, 2026, the Atom Cam 2 successfully booted a minimal Nerves application from a MicroSD card and became reachable over Wi-Fi.

Verified result:

```text
Hostname: nerves.local
IPv4 address: 192.168.10.117
Ping: successful
SSH public-key authentication: successful
Remote shell: interactive IEx
```

The SSH session opened:

```text
Interactive Elixir (1.20.2)
iex(atomcam2_nerves_app@127.0.0.1)>
```

This completed the first network milestone.

## Scope

The milestone proved:

- Boot with the known-good Atom Cam 2 vendor kernel
- Mount an application-merged Nerves SquashFS root filesystem
- Start `erlinit`, the Erlang VM, and the application release
- Prepare the T31 SDIO hardware
- Load the vendor ATBM Wi-Fi driver
- Configure `wlan0` through VintageNet
- Associate with the configured wireless network
- Obtain an IPv4 address through DHCP
- Publish `nerves.local` through mDNS
- Open an SSH session with a public key

Deferred work includes camera capture, RTSP, vendor application compatibility, WebUI, firmware updates, and production hardening.

## Tested platform

```text
Device: Atom Cam 2
SoC: Ingenic T31
Architecture: MIPS32 Release 2, little-endian
Kernel: Linux 3.10.14
Elixir: 1.20.2
ERTS: 17.0.2
Nerves: 1.14.3
VintageNet: 0.13.12
VintageNetWiFi: 0.12.9
```

Wi-Fi hardware:

```text
Module: atbm603x_wifi_sdio.ko
Chip: ATBM 6032i
Interface: wlan0
MAC address: 7C:DD:E9:03:84:B0
```

## Boot structure

The FAT-formatted MicroSD partition contains:

```text
factory_t31_ZMC6tiIDQN
rootfs_hack.squashfs
hostname
authorized_keys
nerves-provisioning.conf
```

The vendor initramfs mounts the card at `/media/mmc`, loop-mounts `rootfs_hack.squashfs`, and switches into the Nerves root filesystem.

The installed image must be the application-merged root filesystem containing:

```text
/srv/erlang
```

The build preserves it as:

```text
examples/atomcam2_nerves_app/_build/atomcam2_prod/nerves/images/rootfs_hack.final.squashfs
```

The flat SD payload is generated under:

```text
examples/atomcam2_nerves_app/_build/atomcam2_prod/nerves/images/atomcam2-sd
```

## Confirmed blockers across the bring-up

The missing ping and SSH result was not caused by one issue. Several sequential blockers had to be removed.

### Dynamic userspace toolchain

The stock Nerves MIPSEL toolchain targeted `24kec` and enabled DSP ASE instructions that the Ingenic T31 did not execute successfully.

Dynamically linked userspace failed with `SIGILL` before the Nerves runtime could start.

The platform now uses a dedicated external toolchain with:

```text
MIPS32 Release 2
little-endian
O32 ABI
soft-float
musl
DSP ASE disabled
```

See [`20260713-atomcam2-toolchain-dsp-ase-investigation.md`](20260713-atomcam2-toolchain-dsp-ase-investigation.md).

### Rootfs and active boot path

The MicroSD card had to contain the final application-merged SquashFS. A stale `rootfs_hack.ext2` or a base system image could cause an older or incomplete userspace to boot instead.

The reliable procedure removes stale alternate rootfs files, verifies checksums, and inspects `/srv/erlang` before hardware testing.

See [`20260714-first-ping-ssh-wifi-and-boot-investigation.md`](20260714-first-ping-ssh-wifi-and-boot-investigation.md).

### SDIO and vendor Wi-Fi driver

The T31 SDIO preparation required `/sbin/devmem` in the early boot environment.

The detected SDIO vendor ID was `0x007a`, which requires the ATBM603x driver. Cross-family fallback to a Realtek module was invalid.

After packaging the compatible vendor module and firmware, `wlan0` appeared with the factory MAC address.

See [`20260714-sdio-wifi-driver-bring-up.md`](20260714-sdio-wifi-driver-bring-up.md).

### VintageNet native `if_monitor`

VintageNet's native process repeatedly terminated with `SIGSEGV` or `SIGBUS`.

Linux 3.10 headers did not define `IFA_FLAGS`. The first compatibility patch defined it as index `8` but left `IFA_MAX` at `7`:

```c
#ifndef IFA_FLAGS
#define IFA_FLAGS 8
#endif
```

VintageNet then accessed `tb[8]` in an array allocated for indexes `0` through `7`, causing an out-of-bounds stack access.

The corrected compatibility block updates both constants:

```c
#ifndef IFA_FLAGS
#define IFA_FLAGS 8
#undef IFA_MAX
#define IFA_MAX IFA_FLAGS
#endif
```

After rebuilding VintageNet:

- `if_monitor` remained running.
- The complete VintageNet supervision tree remained available.
- `VintageNet.configure/3` returned `:ok`.

### Unsupported WPS configuration

After VintageNet configured successfully, `wpa_supplicant` still exited before association.

A temporary wrapper captured the exact parser error:

```text
Line 3: unknown global field 'wps_cred_processing=1'.
Line 3: Invalid configuration line 'wps_cred_processing=1'.
Failed to read or parse configuration
wpa_supplicant_exit_status=255
```

VintageNetWiFi enabled WPS configuration by default, but the Buildroot `wpa_supplicant` binary did not support that global option.

WPS is unnecessary for static SSID and passphrase provisioning, so the permanent configuration disables it:

```elixir
vintage_net_wifi: %{
  wps: false,
  networks: [
    %{
      ssid: ssid,
      psk: passphrase,
      key_mgmt: key_mgmt
    }
  ]
}
```

After this change, Wi-Fi association, DHCP, mDNS, ping, and SSH succeeded.

## Supporting adjustments

The following changes improve reliability but were not isolated as the final root causes by themselves.

### Startup ordering

Shoehorn starts the network-related applications in this order:

```elixir
init: [:nerves_runtime, :vintage_net, :mdns_lite, :nerves_ssh]
```

This keeps VintageNet ahead of network-facing services.

### Interface detection

The included BusyBox `ifconfig` reports:

```text
ifconfig: no support for status display
```

It produced an early false negative for `wlan0`.

Use:

```sh
test -e /sys/class/net/wlan0
ip addr show dev wlan0
```

### Public-key packaging

`authorized_keys` must contain the intended host public key before installing the SD payload.

During bring-up, the file was explicitly copied and its checksum compared between:

- The host public key
- The generated SD payload
- The mounted MicroSD card

The packaging process should keep this deterministic.

## Successful verification

Name resolution returned:

```text
nerves.local=192.168.10.117
```

Ping returned four responses with no packet loss.

SSH succeeded with:

```sh
ssh nerves@192.168.10.117
```

The interactive IEx prompt confirmed the complete path:

```text
MicroSD boot
-> Nerves userspace
-> Erlang release
-> Wi-Fi association
-> DHCP
-> mDNS
-> SSH
```

## Permanent platform changes

The confirmed platform requirements for this milestone are:

1. Use the dedicated non-DSP MIPS32R2 Nerves toolchain.
2. Preserve and package the application-merged SquashFS root filesystem.
3. Remove stale alternate rootfs files before testing.
4. Prepare T31 SDIO and load the matching ATBM603x vendor module.
5. Patch VintageNet `if_monitor.c` by updating both `IFA_FLAGS` and `IFA_MAX` for Linux 3.10.
6. Disable WPS in the VintageNetWiFi configuration.
7. Supply a valid SSH public key in the SD payload.

## Temporary diagnostics removed

The following were investigation-only tools and should not remain in the normal firmware:

- `if_monitor` shell wrapper
- `wpa_supplicant` shell wrapper
- Diagnostic SquashFS images and alternate SD payloads
- Repeated VintageNet property snapshots
- Application-side `wpa_cli`, `iw`, `ip`, and process-list capture
- Temporary native crash logs

Small pre-runtime boot breadcrumbs may remain while the platform is experimental, provided they do not affect normal startup.

## Known follow-up items

### SSH key generation

Ensure a normal firmware build always produces a non-empty and correct `authorized_keys` file without a manual repair step.

### Runtime logging

The successful IEx session reported that the RingLogger backend was not running. This does not affect networking or SSH, but it may be enabled later for in-memory runtime log inspection.

### Kernel independence

The first milestone used the known-good vendor kernel to isolate userspace and networking. A separate milestone should prove the repository-built kernel without changing the already working userspace boundary at the same time.

## Rebuild procedure

From the repository root, use the build wrapper:

```sh
./scripts/patch-vintage-net-linux-3.10.sh
./scripts/build-firmware-log.sh
```

Verify the generated payload:

```sh
./scripts/atomcam2-check-sd-payload.sh \
  examples/atomcam2_nerves_app/_build/atomcam2_prod/nerves/images/atomcam2-sd
```

After installing it to the card, compare the rootfs and public-key checksums before booting.

## Verification procedure

```sh
getent ahostsv4 nerves.local
ping -c 4 nerves.local
ssh nerves@nerves.local
```

A successful SSH connection into IEx confirms the first network milestone.
