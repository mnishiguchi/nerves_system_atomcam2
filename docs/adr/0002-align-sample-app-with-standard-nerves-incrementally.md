# ADR 0002: Align the sample application with standard Nerves conventions incrementally

## Status

Accepted

## Context

The Atom Cam 2 example application originally used project-specific runtime
code for responsibilities that standard Nerves libraries already provide,
including Wi-Fi startup, interactive shell presentation, logging, service
discovery, system time, and SSH state.

The platform does not use the ordinary Nerves firmware-partition layout. It
boots a flat MicroSD payload containing the protected Atom Cam 2 kernel and a
SquashFS root filesystem. As a result, some standard Nerves assumptions do not
apply:

- Firmware installation must continue through `mix atomcam2.install`.
- Remote firmware upload must remain rejected.
- The active firmware metadata cannot be read from a conventional U-Boot
  environment or application partition.
- Writable runtime state must be stored on `/media/mmc`.
- The platform does not expose standard application-partition usage or thermal
  sensor data.

A single large replacement would make regressions difficult to isolate on
hardware. The application therefore needed to move toward standard Nerves
conventions through small, independently verified changes.

## Decision

### Preserve the platform boundary

Keep the existing Atom Cam 2 boot and installation contract:

- Preserve the verified Atom Cam 2 control kernel.
- Continue producing the flat MicroSD payload.
- Use `mix atomcam2.install` for installation.
- Reject unsupported remote firmware updates.
- Do not represent the platform as having a standard Nerves application
  partition when it does not.

Standardize the application runtime without redesigning the underlying platform
workflow.

### Adopt standard Nerves runtime services explicitly

Use focused Nerves libraries for the services the example application needs:

- `NervesMOTD` for the IEx greeting
- `RingLogger` for retained runtime logs
- `NervesSSH` for remote IEx access
- `MdnsLite` for SSH, SFTP, and Nerves device advertisements
- `VintageNet` and `VintageNetWiFi` for Wi-Fi configuration
- `NervesTime` for approximate startup time and NTP synchronization
- `Nerves.Runtime` for runtime firmware metadata

Declare these dependencies explicitly rather than adopting `nerves_pack`.
The application needs project-specific configuration for several services and
does not need the direct-link networking or DHCP-server behavior that the bundle
would add.

### Let VintageNet own Wi-Fi configuration

Build the default `wlan0` configuration in `config/runtime.exs` from the
provisioning data on `/media/mmc`.

Remove the custom network worker only after the VintageNet configuration has
been verified on hardware. Application code must not reconfigure `wlan0` after
VintageNet starts.

Retain credential-safe diagnostics, but do not expose the Wi-Fi passphrase.

### Store writable runtime state on the MicroSD partition

Use `/media/mmc` for state that must survive reboot:

- `/media/mmc/nerves-firmware-metadata.conf`
- `/media/mmc/.nerves_time`
- `/media/mmc/nerves_ssh`

Generate the firmware metadata file from the actual `.fw` artifact during
installation and load it through `Nerves.Runtime.KVBackend.InMemory`.

Persist SSH host keys under `/media/mmc/nerves_ssh` because `/data` is read-only
on this platform.

### Synchronize time when Internet access becomes available

Allow `NervesTime` to restore an approximate timestamp from
`/media/mmc/.nerves_time`.

Subscribe to the VintageNet `wlan0` connection property and restart `ntpd` when
the interface reaches `:internet` and time is not yet synchronized. This process
does not configure networking; VintageNet remains the sole owner of the
interface.

### Advertise only required discovery services

Advertise:

- `_ssh._tcp`
- `_sftp-ssh._tcp`
- `_nerves-device._tcp`

Do not enable the mDNS DNS bridge until application code requires generic
outbound `.local` resolution through the Erlang resolver. Direct `MdnsLite`
resolution remains available when explicitly needed.

### Keep Erlang distribution local

Keep the release node and Erlang distribution bound to `127.0.0.1`.

Use NervesSSH for remote administration instead of exposing raw distributed
Erlang. Preserve the verified `rel/vm.args.eex` configuration unless a concrete
requirement justifies changing it.

### Verify incrementally on hardware

Implement each runtime change independently and verify it on an Atom Cam 2
before removing replaced code or proceeding to the next responsibility.

Repository checks, firmware construction, MicroSD installation, boot, Wi-Fi,
SSH, discovery, metadata, persistent state, and time synchronization must all
pass before considering the alignment complete.

## Consequences

### Positive

- The example application follows familiar Nerves runtime patterns.
- Network ownership is explicit and no longer duplicated by a custom worker.
- Logging, MOTD, SSH, discovery, metadata, and time behavior are easier to
  understand and maintain.
- Firmware identity, approximate time, and SSH host identity survive the custom
  flat-MicroSD workflow.
- Hardware regressions are easier to isolate because the migration was performed
  incrementally.

### Negative

- The custom installer and metadata bridge remain necessary because the platform
  does not use the standard Nerves firmware-partition layout.
- A small application process is required to prompt NTP synchronization when
  Internet connectivity appears after `NervesTime` starts.
- NervesMOTD continues to report application-partition usage and temperature as
  unavailable because the platform does not expose those data sources.
- The mDNS DNS bridge remains deferred and must be reconsidered if outbound
  `.local` resolution becomes a requirement.

## Related documentation

- `docs/worklog/20260717-align-example-app-with-standard-nerves.md`
