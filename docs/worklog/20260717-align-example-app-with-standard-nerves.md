# Align the example application with standard Nerves conventions

## Overview

Most of this work was completed on July 17, 2026. Final verification and the
automatic NTP recovery fix were completed on July 18, 2026.

Related decision record:

- `docs/adr/0002-align-sample-app-with-standard-nerves-incrementally.md`

Branch:

- `feat/align-example-app-adr-0002`

The goal was to replace project-specific application behavior with standard
Nerves services without changing the proven Atom Cam 2 boot and MicroSD
installation workflow.

This worklog keeps the findings, solutions, and hardware evidence that remain
useful after the implementation. It is not a command transcript.

## Platform constraints

The example application runs on a nonstandard Nerves platform boundary:

- The device boots a flat MicroSD payload.
- The protected kernel file is `factory_t31_ZMC6tiIDQN`.
- The verified kernel SHA-256 is
  `b50658eac32b57fdcb20383d82a54e6439acd7a3f7e9cb8b43edf4a4b89b03bc`.
- The root filesystem is SquashFS.
- The writable MicroSD mount on the device is `/media/mmc`.
- Firmware installation uses `mix atomcam2.install`.
- Ordinary `mix burn` and `mix upload` are not supported for this workflow.
- Wi-Fi provisioning is read from
  `/media/mmc/nerves-provisioning.conf`.
- Remote firmware updates remain deliberately rejected.

These constraints were treated as platform behavior rather than application
problems to remove.

## Final result

The example application now uses:

- NervesMOTD with a generated Atom Cam 2 ANSI logo
- Toolshed in remote IEx sessions
- RingLogger
- NervesSSH
- SSH and SFTP mDNS advertisements
- Nerves device discovery metadata
- VintageNet runtime Wi-Fi configuration
- Nerves Runtime KV firmware metadata
- NervesTime with persistent approximate time
- Persistent SSH host keys
- Automatic NTP restart when Internet connectivity becomes available

The custom network worker was removed after VintageNet behavior was verified on
hardware.

## Implementation findings and solutions

### NervesMOTD and IEx startup

`/etc/iex.exs` now has two responsibilities:

- Print `NervesMOTD`.
- Import Toolshed.

The Atom Cam 2 logo is implemented in
`Atomcam2NervesApp.MOTDLogo` and supplied through NervesMOTD configuration.
Keeping rendering out of `iex.exs` makes the shell startup file conventional and
keeps the logo independently testable.

NervesMOTD correctly displays product, version, firmware UUID, platform, and
architecture after runtime metadata is provided.

Two displayed fields remain unavailable:

- `Part usage`: the platform has no conventional Nerves application partition.
- `Temperature`: the kernel exposes no standard thermal zone or hardware
  monitoring input.

Copying or forking the NervesMOTD renderer only to hide these honest values was
not justified.

### RingLogger

RingLogger was activated as the target logger backend.

Hardware verification confirmed:

- The application started `:ring_logger`.
- Recent boot logs were retained.
- Newly emitted Logger messages appeared in the ring buffer.

This became useful while checking VintageNet, SSH, and time behavior during
subsequent milestones.

### SSH and SFTP discovery

The device advertises these services through MdnsLite:

- `_ssh._tcp` on port 22
- `_sftp-ssh._tcp` on port 22

Both services include PTR, SRV, and TXT records and were discoverable from the
development machine.

### Nerves device discovery metadata

The application registers `_nerves-device._tcp` with:

- Serial number
- Application version
- Product
- Description
- Platform
- Architecture

The SRV record uses port 0 because the service describes the device rather than
a network endpoint.

Both `avahi-browse` and `mix nerves.discover` found the device.

### mDNS DNS bridge

Direct MdnsLite resolution worked:

```elixir
MdnsLite.gethostbyname("thinkpad.local")
```

The ordinary Erlang resolver did not resolve the same `.local` host:

```elixir
:inet.gethostbyname(~c"thinkpad.local")
:inet.getaddr(~c"thinkpad.local", :inet)
```

The application has no current feature that opens outbound connections to
`.local` hosts. Enabling a local DNS listener and changing resolver
configuration would add complexity without a consumer.

The bridge was therefore deferred. Use direct MdnsLite resolution for explicit
cases and reconsider the bridge when generic outbound `.local` resolution is
required.

### Runtime Wi-Fi configuration

`config/runtime.exs` converts the MicroSD provisioning data into VintageNet's
default `wlan0` configuration.

The verified configuration uses:

- `VintageNetWiFi`
- DHCP
- WPA-PSK
- `wps: false`

The original custom network worker was initially retained as a migration
fallback. Verification showed that it recognized the existing VintageNet
configuration and did not reconfigure `wlan0`.

The worker was then removed. The application supervisor no longer owns Wi-Fi
configuration, and VintageNet connects successfully without it.

The remaining Wi-Fi diagnostic helper returns redacted structural information
and does not expose credentials.

### Runtime firmware metadata

The flat MicroSD workflow does not provide the usual writable U-Boot environment
used by standard Nerves firmware metadata.

The solution is to generate
`nerves-firmware-metadata.conf` from the actual `.fw` artifact during
`mix atomcam2.install`.

The file contains:

```text
nerves_fw_active=a
a.nerves_fw_product=atomcam2_nerves_app
a.nerves_fw_version=0.1.0
a.nerves_fw_uuid=<generated firmware UUID>
a.nerves_fw_platform=atomcam2
a.nerves_fw_architecture=mipsel
```

At runtime, `Nerves.Runtime.KVBackend.InMemory` loads this file from
`/media/mmc`.

Generating the file from the firmware artifact prevents stale or hard-coded UUID
values.

### Persistent time and NTP synchronization

The device has no battery-backed real-time clock.

NervesTime stores an approximate timestamp in:

```text
/media/mmc/.nerves_time
```

This prevents the clock from starting at 1970 while the device is offline or
waiting for network connectivity.

A final full-boot verification exposed a startup race:

- NervesTime started before Wi-Fi had Internet access.
- The clock remained unsynchronized after the interface reached `:internet`.
- Calling `NervesTime.restart_ntpd/0` immediately led to successful
  synchronization.

The durable fix is `Atomcam2NervesApp.TimeSync`:

- Subscribe to
  `["interface", "wlan0", "connection"]`.
- Check the current connection during initialization.
- When the connection reaches `:internet`, restart `ntpd` only when NervesTime
  is not already synchronized.
- Do not configure or own the interface.

Final hardware verification confirmed automatic synchronization at stratum 3
without an operator calling `NervesTime.restart_ntpd/0`.

### Persistent SSH host keys

NervesSSH defaults to paths under `/data`, but `/data` is read-only on this
platform.

Before the fix, NervesSSH logged filesystem errors and fell back to paths under
`/tmp/nerves_ssh`. The host key was therefore regenerated on every reboot,
causing SSH known-host warnings.

NervesSSH now uses:

```text
system_dir: /media/mmc/nerves_ssh
user_dir: /media/mmc/nerves_ssh/default_user
```

The writable MicroSD partition preserves:

- The SSH host key
- The authorized-key state

The ED25519 fingerprint remained identical across reboot:

```text
SHA256:FV/R0bGaCv9BMqCaBTTk3QYi+fMxXsZP5dv/sFXdMuc
```

### Explicit dependencies instead of nerves_pack

`nerves_pack` was evaluated but not adopted.

The example application directly configures several runtime services and does
not need direct-link networking or a DHCP server. Explicit dependencies make
the runtime contract easier to understand and avoid bringing in unneeded
services.

The following direct dependencies remain justified:

- `shoehorn`
- `ring_logger`
- `toolshed`
- `nerves_time`
- `nerves_motd`
- `nerves_runtime`
- `nerves_ssh`
- `mdns_lite`
- `vintage_net`
- `vintage_net_wifi`

No dependency became redundant when the custom network worker was removed.

### VM arguments

The release keeps distributed Erlang on loopback:

```text
-name <release-name>@127.0.0.1
-kernel inet_dist_use_interface {127,0,0,1}
-noshell
```

Remote administration is provided through NervesSSH rather than raw EPMD and
distributed Erlang.

The existing configuration was retained because it is hardware-verified and
there is no concrete requirement to expose or redesign distribution.

## Final hardware evidence

Final firmware:

- Firmware name: `labor-fossil`
- Firmware UUID: `7a673074-5e8d-5605-6d3c-5b61c9c4934d`
- Product: `atomcam2_nerves_app`
- Version: `0.1.0`
- Platform: `atomcam2`
- Architecture: `mipsel`

Runtime verification:

- The application started successfully.
- `wlan0` received `192.168.10.117/24` through DHCP.
- Wi-Fi used WPA-PSK with WPS disabled.
- `_ssh._tcp`, `_sftp-ssh._tcp`, and `_nerves-device._tcp` were advertised.
- `/media/mmc/nerves_ssh` contained
  `ssh_host_ed25519_key` and the `default_user` directory.
- The TimeSync process was running.
- VintageNet reported `:internet`.
- NervesTime synchronized automatically at stratum 3.
- The final measured offset was approximately -2.8 milliseconds.

## Repository verification

The completed implementation passed:

```text
git diff --check main...HEAD
./scripts/smoke-check.sh
mix deps.get
mix compile --warnings-as-errors
mix firmware
mix atomcam2.install --dry-run
mix atomcam2.install
```

The final build and dry-run left the repository working tree clean.

The firmware build attempted to download a prebuilt system artifact for version
`0.1.0`, received a 404, and correctly fell back to building the local system.
This is expected until a matching release artifact is published.

## Generated files that must not be committed

Standard Nerves tooling may generate these paths in the example application
directory:

```text
atomcam2_nerves_app
nerves
upload.sh
```

In this workflow they are not used for installation and must not be committed.
The supported installation command remains:

```text
mix atomcam2.install
```

## Commit sequence

The implementation was completed through small commits:

```text
6f545e2 docs(adr): add ADR 0002 implementation checklist
400262c feat(example): add NervesMOTD to IEx sessions
780af9f feat(example): activate RingLogger on the target
f8c3b1e docs(example): document local direnv configuration
e6063c7 feat(example): advertise SSH services over mDNS
2bbee57 feat(example): advertise Nerves discovery metadata
255b6f6 docs(adr): defer mDNS DNS bridge
1e6c523 feat(example): configure Wi-Fi at runtime
a4760f7 feat(example): add Atom Cam 2 MOTD logo
de82b00 refactor(example): remove custom network worker
75f68a3 fix(example): provide firmware metadata at runtime
57b1e4e feat(example): synchronize system time
8564f32 fix(example): persist SSH host keys
6715fcd docs(adr): record verified example milestones
18e7398 docs(adr): record remaining convention decisions
9c5fc31 fix(example): restart NTP when internet becomes available
7b0e970 docs(adr): complete example application alignment
```

## Outcome

ADR 0002 is implemented.

The application now follows standard Nerves runtime conventions where they fit,
while the custom Atom Cam 2 platform boundary remains explicit and unchanged.
