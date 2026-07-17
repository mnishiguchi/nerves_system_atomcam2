# ADR 0002: Align the sample application with standard Nerves conventions incrementally

## Status

Accepted on July 16, 2026.

## Context

The example application should resemble a conventional Nerves application such as `circuits_quickstart` where practical.

A previous refactor attempted to adopt several standard application conventions at once, including new dependencies, `nerves_pack`, Shoehorn changes, runtime network configuration, service discovery, logging, MOTD, and IEx helpers.

The resulting firmware no longer provided reliable Wi-Fi, `nerves.local`, ping, or SSH. Because many responsibilities changed together, the regression could not be attributed safely to one package or configuration change.

The Atom Cam 2 system also has target-specific requirements that a standard example application does not have:

- A custom MIPS32R2 soft-float toolchain.
- A vendor-compatible kernel and initramfs boot handoff.
- Vendor SDIO preparation and Wi-Fi module loading before BEAM starts.
- Linux 3.10 compatibility for VintageNet.
- WPS disabled in the Wi-Fi configuration.
- A flat-file MicroSD installation contract.

These requirements must remain stable while the application is simplified.

## Decision

Use `circuits_quickstart` as a reference, not as a template to copy wholesale.

### Preserve the platform boundary

Application refactoring must not modify the following in the same change:

- The custom Nerves system.
- The toolchain or Buildroot configuration.
- The kernel or initramfs handoff.
- Vendor Wi-Fi preparation.
- The flat-SD packaging and installation flow.
- Verified target compatibility adjustments.

The hardware-verified application workflow remains:

```sh
mix setup
mix firmware
mix atomcam2.install
```

### Refactor incrementally

Introduce one independently testable behavior at a time.

Examples include:

- Toolshed startup.
- NervesMOTD.
- RingLogger.
- Additional mDNS services.
- `nerves_pack`.
- Runtime Wi-Fi configuration.
- Removal of custom application supervision.

Do not combine dependency changes, service ownership changes, application renaming, network configuration changes, and packaging changes in one refactor.

`nerves_pack` may be adopted only after the services it owns have been tested individually and duplicate ownership has been removed deliberately.

Existing custom application code must remain until its standard replacement has passed hardware verification.

### Require hardware verification

Each meaningful milestone must pass:

```sh
git diff --check
./scripts/smoke-check.sh

cd examples/atomcam2_nerves_app

mix setup
mix firmware
mix atomcam2.install
```

After power-cycling the camera:

```sh
ping nerves.local
ssh nerves@nerves.local
```

The SSH IEx session must also confirm:

```elixir
node()
exit()
```

A milestone must be committed separately before starting the next one.

If verification fails, return to the most recent hardware-verified commit before investigating or attempting another refactor.

## Consequences

The migration will require more, smaller commits and repeated hardware tests.

This is accepted because regressions remain attributable to a narrow change and the custom Atom Cam 2 system stays recoverable.

The final example application may intentionally differ from `circuits_quickstart` where the target boot, networking, provisioning, or installation contract requires it.

The refactor is complete when the application follows the selected standard Nerves conventions without changing the verified platform behavior. Matching the exact dependency list or directory structure of `circuits_quickstart` is not a goal.

## Implementation checklist

- [x] Establish and record the clean baseline.
- [x] Add NervesMOTD without changing application supervision or networking.
- [x] Activate RingLogger on the target.
- [x] Advertise standard SSH-related mDNS services.
- [x] Advertise Nerves device metadata.
- [x] Evaluate the mDNS DNS bridge.
- [x] Add runtime Wi-Fi credentials without removing existing sources.
- [x] Evaluate `nerves_pack` before adopting it.
- [x] Remove dependencies made redundant by verified replacements.
- [x] Simplify custom Wi-Fi supervision only after replacement behavior is verified.
- [x] Review VM argument conventions independently.
- [ ] Complete final repository and hardware verification.

## Implementation progress

### Milestone 1: NervesMOTD

Implementation status: implemented and hardware-verified on July 17, 2026.

Changes are limited to the example application:

- Add `nerves_motd` as a target dependency.
- Configure a simple Atom Cam 2 logo.
- Print the MOTD before importing Toolshed in `/etc/iex.exs`.
- Preserve the existing supervision tree, networking, SSH, packaging, and platform boundary.

Required verification:

- [x] `git diff --check`
- [x] `./scripts/smoke-check.sh`
- [x] `mix setup`
- [x] `mix firmware`
- [x] `mix atomcam2.install`
- [x] Wi-Fi connects after power-up.
- [x] `nerves.local` resolves and responds to ping.
- [x] SSH opens an IEx session.
- [x] The Atom Cam 2 MOTD appears before the IEx prompt.
- [x] Toolshed remains imported.
- [x] `node()` and `exit()` behave as expected.

Hardware evidence:

- Verified control kernel:
  - SHA-256: `b50658eac32b57fdcb20383d82a54e6439acd7a3f7e9cb8b43edf4a4b89b03bc`
  - Size: `1976325 bytes`
- Firmware UUID: `d7695134-40f6-5b64-8252-46aa4cc99413`
- Firmware name: `spy-gap`
- `nerves.local` resolved to `192.168.10.117`.
- Ping completed with four replies and zero packet loss.
- SSH opened `atomcam2_nerves_app@127.0.0.1`.
- NervesMOTD printed `Atom Cam 2 running Nerves` before the IEx prompt.
- Toolshed was imported and `cmd/1` executed successfully.
- NervesMOTD, NervesRuntime, NervesSSH, mDNS, VintageNet, VintageNetWiFi, and the example application were started.
- VintageNet reported `wlan0` configured with an internet connection and `wps: false`.
- Remote `mix upload nerves.local` was rejected with instructions to use `mix atomcam2.install`.

The missing `uname` command is a property of the minimal BusyBox configuration and does not indicate a Toolshed failure. The incomplete firmware metadata shown as `unknown 0.0.0 - unknown` is outside this milestone.

### Milestone 2: RingLogger

Implementation status: hardware-verified on July 17, 2026.

Changes are limited to the example application's target logging configuration:

- Configure RingLogger as the target Logger backend.
- Remove the default console backend through the standard Logger backend configuration.
- Preserve NervesMOTD, Toolshed, supervision, networking, SSH, packaging, and the platform boundary.

Verification:

- [x] `git diff --check`
- [x] `./scripts/smoke-check.sh`
- [x] `mix firmware`
- [x] `mix atomcam2.install`
- [x] Wi-Fi connects after power-up.
- [x] `nerves.local` resolves and responds to ping.
- [x] SSH opens an IEx session.
- [x] NervesMOTD and Toolshed remain available.
- [x] `:ring_logger` is started.
- [x] Recent boot logs are available through `RingLogger.tail/1`.
- [x] A new Logger message is retained in the ring buffer.
- [x] Remote firmware upload remains rejected.

Hardware evidence:

- Firmware name: `two-beach`
- Firmware UUID: `f01658b9-ba23-5049-8841-f84b19560894`
- `nerves.local` responded to 3 of 3 ping requests with 0% packet loss.
- SSH opened an IEx session and displayed NervesMOTD.
- Toolshed was imported successfully.
- RingLogger `0.11.6` was present in the started applications.
- `RingLogger.tail(20)` returned retained boot and network logs.
- `RingLogger.grep/1` found `ADR 0002 RingLogger hardware verification`.
- The NervesSSH process remained stable during a 10-second observation.
- VintageNet reported `wlan0` configured with internet connectivity.
- `mix upload nerves.local` was rejected with instructions to use `mix atomcam2.install`.

A transient NervesSSH startup failure and read-only `/data/nerves_ssh`
fallback were observed in the retained boot logs. SSH recovered and remained
stable, so these findings do not block this milestone.

### Milestone 3: SSH-related mDNS services

Implementation status: hardware-verified on July 17, 2026.

Changes are limited to the existing `mdns_lite` target configuration:

- Advertise the SSH service as `_ssh._tcp` on port 22.
- Advertise the SFTP service as `_sftp-ssh._tcp` on port 22.
- Preserve the existing `nerves.local` hostname advertisement.
- Preserve NervesMOTD, RingLogger, Toolshed, networking, SSH, packaging, and the platform boundary.

Verification:

- [x] `git diff --check`
- [x] `./scripts/smoke-check.sh`
- [x] `mix firmware`
- [x] `mix atomcam2.install`
- [x] Wi-Fi connects after power-up.
- [x] `nerves.local` resolves and responds to ping.
- [x] SSH opens an IEx session.
- [x] NervesMOTD, RingLogger, and Toolshed remain available.
- [x] `MdnsLite.Info.dump_records/0` contains `_ssh._tcp` PTR, SRV, and TXT records.
- [x] `MdnsLite.Info.dump_records/0` contains `_sftp-ssh._tcp` PTR, SRV, and TXT records.
- [x] A host-side mDNS browser discovers both services on port 22.
- [x] Remote firmware upload remains rejected.

Hardware evidence:

- Firmware name: `fox-invest`
- Firmware UUID: `6480dd3a-c504-52fd-fcb1-efe8600dad61`
- `nerves.local` responded to 3 of 3 ping requests with 0% packet loss.
- SSH opened an IEx session and displayed NervesMOTD.
- Toolshed was imported successfully.
- `Application.fetch_env!(:mdns_lite, :services)` returned the SSH and SFTP service definitions.
- `_ssh._tcp.local` contained PTR, SRV, and TXT records.
- `_sftp-ssh._tcp.local` contained PTR, SRV, and TXT records.
- Both SRV records targeted `nerves.local` on port 22.
- `avahi-browse` discovered both services at `192.168.10.117` on port 22.
- RingLogger remained operational and retained recent device logs.
- `mix upload nerves.local` was rejected with instructions to use `mix atomcam2.install`.

### Milestone 4: Nerves device discovery metadata

Implementation status: hardware-verified on July 17, 2026.

The standard Nerves discovery service is registered during example application
startup through the existing `mdns_lite` process.

At this milestone, the custom Atom Cam 2 SD boot path did not yet expose the
usual active firmware KV metadata. The advertisement therefore used runtime and
application values that remained available:

- Serial number from `Nerves.Runtime.serial_number/0`
- Version from the example application's application specification
- Explicit Atom Cam 2 product, description, and platform values
- Architecture derived from the Erlang runtime architecture

Verification:

- [x] `git diff --check`
- [x] `./scripts/smoke-check.sh`
- [x] `mix compile`
- [x] `mix firmware`
- [x] `mix atomcam2.install`
- [x] Wi-Fi connects after power-up.
- [x] `nerves.local` resolves and responds to ping.
- [x] SSH opens an IEx session.
- [x] `_nerves-device._tcp` is registered automatically after boot.
- [x] The service contains PTR, SRV, and TXT records.
- [x] The SRV record targets `nerves.local` on port 0.
- [x] The TXT record contains serial, version, product, description, platform, and architecture.
- [x] `avahi-browse` discovers the service.
- [x] `mix nerves.discover` displays the device metadata.
- [x] SSH and SFTP mDNS services remain available.
- [x] Remote firmware upload remains rejected.

Hardware evidence:

- Firmware name: `cushion-camera`
- Firmware UUID: `40264b6d-07d9-52ec-02db-5ec874d93fe4`
- `nerves.local` responded to 3 of 3 ping requests with 0% packet loss.
- `_nerves-device._tcp.local` contained PTR, SRV, and TXT records.
- The SRV record targeted `nerves.local` on port 0.
- The TXT record advertised serial `86010000a9a2`.
- The TXT record advertised version `0.1.0`.
- The TXT record advertised product `atomcam2_nerves_app`.
- The TXT record advertised platform `atomcam2`.
- The TXT record advertised architecture `mipsel`.
- `avahi-browse` resolved the service at `192.168.10.117`.
- `mix nerves.discover` displayed the hostname, address, serial, product, version, and platform.
- `mix upload nerves.local` was rejected with instructions to use `mix atomcam2.install`.

### Milestone 5: Evaluate the mDNS DNS bridge

Implementation status: evaluated and deferred on July 17, 2026.

`MdnsLite` can resolve other `.local` hosts directly, but the Erlang resolver
does not currently route `.local` queries through `MdnsLite`.

Runtime evidence:

- `MdnsLite.gethostbyname("thinkpad.local")` returned
  `{:ok, {192, 168, 10, 111}}`.
- `:inet.gethostbyname/1` returned `{:error, :nxdomain}`.
- `:inet.getaddr/2` returned `{:error, :nxdomain}`.
- `:mdns_lite` has no `:dns_bridge_enabled` configuration.
- `:vintage_net` has no `:additional_name_servers` configuration.
- The Erlang resolver uses `lookup: [:native]`.

The bridge would allow ordinary Erlang networking functions to resolve
`.local` names. The current example application does not initiate outbound
connections to `.local` hosts, so this capability has no present consumer.

Decision:

- Do not enable the mDNS DNS bridge.
- Preserve direct `MdnsLite` resolution for cases that explicitly require it.
- Reconsider the bridge when an application feature needs generic outbound
  `.local` hostname resolution through `:inet`, `:gen_tcp`, or `:gen_udp`.
- Avoid adding a local DNS listener and resolver configuration until required.

Verification:

- [x] Confirm direct `MdnsLite` resolution of another `.local` host.
- [x] Confirm the ordinary Erlang resolver does not resolve the same host.
- [x] Inspect the current `mdns_lite`, `vintage_net`, and Erlang resolver configuration.
- [x] Confirm the example application has no current consumer of generic outbound `.local` resolution.
- [x] Record the decision without changing runtime behavior.

### Milestone 6: Runtime Wi-Fi configuration

Implementation status: hardware-verified on July 17, 2026.

Wi-Fi credentials from `/media/mmc/nerves-provisioning.conf` are now converted
into the default VintageNet `wlan0` configuration by `config/runtime.exs`.

The existing network worker remains as a fallback during the migration. It
preserves an existing VintageNet Wi-Fi configuration and retains the previous
provisioning-file, process-environment, and `wpa_supplicant.conf` sources.

The configuration continues to use DHCP and explicitly disables WPS.

Verification:

- [x] `git diff --check`
- [x] `./scripts/smoke-check.sh`
- [x] `mix compile`
- [x] `mix firmware`
- [x] `mix atomcam2.install`
- [x] Wi-Fi connects automatically after power-up.
- [x] The active interface type is `VintageNetWiFi`.
- [x] The active IPv4 method is DHCP.
- [x] The configured network uses WPA-PSK.
- [x] WPS remains disabled.
- [x] `Application.get_env(:vintage_net, :config)` contains the `wlan0` default.
- [x] The custom worker preserves the existing VintageNet configuration.
- [x] The custom worker does not reconfigure `wlan0`.
- [x] Existing credential fallback sources remain implemented.
- [x] SSH opens an IEx session.
- [x] SSH, SFTP, and Nerves discovery mDNS services remain available.
- [x] `mix nerves.discover` continues to find the device.
- [x] Remote firmware upload remains rejected.

Hardware evidence:

- Firmware name: `all-cherry`
- Firmware UUID: `0f30b1f7-eeb0-5750-4083-b082ffe51891`
- VintageNet connected `wlan0` to the provisioned network.
- The device received `192.168.10.117/24` through DHCP.
- The effective configuration used `VintageNetWiFi`, WPA-PSK, and `wps: false`.
- The VintageNet application environment contained the runtime `wlan0` default.
- RingLogger confirmed that the network worker kept the existing configuration.
- RingLogger contained no custom-worker `Configuring wlan0` entry.
- `_ssh._tcp`, `_sftp-ssh._tcp`, and `_nerves-device._tcp` remained advertised.
- `avahi-browse` resolved the Nerves discovery service.
- `mix nerves.discover` displayed the expected device metadata.
- `mix upload nerves.local` was rejected with instructions to use `mix atomcam2.install`.

### Milestone 7: Custom NervesMOTD logo

Implementation status: hardware-verified on July 17, 2026.

The example application now provides a generated ANSI illustration of the
Atom Cam 2 as the NervesMOTD logo.

The illustration is implemented in
`Atomcam2NervesApp.MOTDLogo` and configured through `config/runtime.exs`.
The IEx startup file remains responsible only for printing NervesMOTD and
importing Toolshed.

Verification:

- [x] `git diff --check`
- [x] `./scripts/smoke-check.sh`
- [x] `mix compile`
- [x] `mix firmware`
- [x] `mix atomcam2.install`
- [x] SSH displays the custom logo automatically.
- [x] The logo contains the `ATOM CAM 2` title.
- [x] The rendered logo contains multiple ANSI foreground and background colors.
- [x] `NervesMOTD.print/0` obtains the logo from application configuration.
- [x] `/etc/iex.exs` contains no logo implementation or rendering call.
- [x] Toolshed remains available.
- [x] SSH, SFTP, and Nerves discovery mDNS services remain available.

Hardware evidence:

- Firmware name: `ostrich-say`
- Firmware UUID: `a4cdf475-b761-5d8e-f5dc-24140de265b7`
- The custom Atom Cam 2 illustration appeared automatically when SSH opened IEx.
- The configured logo was 8,258 bytes.
- The configured logo contained 45 distinct ANSI color pairs.
- The configured logo contained the `ATOM CAM 2` title.
- `/etc/iex.exs` remained `NervesMOTD.print()` followed by `use Toolshed`.
- `_ssh._tcp`, `_sftp-ssh._tcp`, and `_nerves-device._tcp` remained advertised.

### Milestone 8: Remove the custom network worker

Implementation status: hardware-verified on July 17, 2026.

The example application no longer starts or includes
`Atomcam2NervesApp.Network`.

VintageNet now owns Wi-Fi configuration and startup through the configuration
created by `config/runtime.exs`. The application retains only a credential-safe
debug helper for inspecting the effective Wi-Fi configuration.

Verification:

- [x] `git diff --check`
- [x] `./scripts/smoke-check.sh`
- [x] Warning-free `mix compile`
- [x] `mix firmware`
- [x] `mix atomcam2.install`
- [x] The custom network source file is removed.
- [x] The custom network BEAM module is absent from the release.
- [x] Application source contains no reference to the custom network module.
- [x] The application starts with an empty supervisor.
- [x] Wi-Fi connects automatically without the custom worker.
- [x] The active interface uses `VintageNetWiFi`.
- [x] The active IPv4 method is DHCP.
- [x] WPA-PSK remains enabled.
- [x] WPS remains disabled.
- [x] The Wi-Fi debug helper does not expose credentials.
- [x] SSH, SFTP, and Nerves discovery mDNS services remain available.

Hardware evidence:

- Firmware name: `margin-focus`
- Firmware UUID: `8f5c1154-8d1e-54ec-ea1a-956a228a7676`
- `Atomcam2NervesApp.Network` was not loaded.
- `Atomcam2NervesApp.Supervisor` had no supervised children.
- `atomcam2_nerves_app` remained started.
- VintageNet connected `wlan0` to the provisioned network through DHCP.
- The effective configuration used WPA-PSK with `wps: false`.
- `_ssh._tcp`, `_sftp-ssh._tcp`, and `_nerves-device._tcp` remained advertised.

### Milestone 9: Runtime firmware metadata

Implementation status: hardware-verified on July 18, 2026.

The Atom Cam 2 installer now extracts metadata from the generated firmware
artifact and writes it to
`nerves-firmware-metadata.conf` in the final MicroSD payload.

At runtime, the example application loads this file through
`Nerves.Runtime.KVBackend.InMemory`. This provides the standard active firmware
metadata expected by Nerves Runtime and NervesMOTD without requiring a writable
U-Boot environment.

The metadata is generated from the actual `.fw` artifact rather than being
hard-coded, so the firmware UUID remains accurate for every build.

Verification:

- [x] `git diff --check`
- [x] `./scripts/smoke-check.sh`
- [x] `mix compile`
- [x] `mix firmware`
- [x] `mix atomcam2.install --dry-run`
- [x] `mix atomcam2.install`
- [x] The metadata file is generated from the built firmware.
- [x] The metadata file is validated before installation.
- [x] The metadata file is copied to the MicroSD card.
- [x] Nerves Runtime uses the in-memory KV backend.
- [x] Product, version, UUID, platform, and architecture are available through `Nerves.Runtime.KV`.
- [x] NervesMOTD displays the correct firmware designation.
- [x] NervesMOTD displays the correct platform and architecture.

Hardware evidence:

- Firmware name: `zebra-hello`
- Firmware UUID: `fc70a0ed-52ad-59c6-a1c8-0013552d8e1b`
- The active firmware slot was `a`.
- The product was `atomcam2_nerves_app`.
- The version was `0.1.0`.
- The platform was `atomcam2`.
- The architecture was `mipsel`.
- NervesMOTD displayed the firmware name, UUID, product, version, platform, and architecture.

### Milestone 10: System time synchronization

Implementation status: hardware-verified on July 18, 2026.

The example application now includes `nerves_time`.

Approximate time is persisted to `/media/mmc/.nerves_time`, allowing the device
to start from a recent timestamp despite having no battery-backed real-time
clock. NervesTime then synchronizes the system clock through NTP after network
connectivity becomes available.

NervesMOTD now identifies the clock as unsynchronized until NTP synchronization
has been confirmed.

Verification:

- [x] `git diff --check`
- [x] `./scripts/smoke-check.sh`
- [x] `mix compile`
- [x] `mix firmware`
- [x] `mix atomcam2.install`
- [x] BusyBox provides `ntpd`.
- [x] BusyBox provides `date`.
- [x] The Erlang VM uses `multi_time_warp`.
- [x] The MicroSD time file is writable.
- [x] Startup time is restored from the persisted time file.
- [x] NervesMOTD marks time as unsynchronized before NTP confirmation.
- [x] NervesTime acquires synchronization after network startup.
- [x] The persisted time file is updated after synchronization.

Hardware evidence:

- NervesTime reported `synchronized?: true`.
- The synchronized source reported stratum 3.
- The final measured offset was approximately -9 milliseconds.
- The clock advanced to the current 2026 UTC date.
- The time file modification timestamp was updated after synchronization.
- A subsequent boot started near the persisted timestamp instead of 1970.

### Milestone 11: Persistent SSH host keys

Implementation status: hardware-verified on July 18, 2026.

NervesSSH now stores its system and user state under
`/media/mmc/nerves_ssh`.

The custom root filesystem keeps `/data` read-only, so the standard NervesSSH
paths previously fell back to `/tmp`. That fallback generated a new SSH host
key after every reboot. Using the writable MicroSD partition preserves the host
identity while retaining the existing authorized-key authentication.

Verification:

- [x] `git diff --check`
- [x] `./scripts/smoke-check.sh`
- [x] `mix compile`
- [x] `mix firmware`
- [x] `mix atomcam2.install`
- [x] The NervesSSH system directory is on the writable MicroSD partition.
- [x] The NervesSSH user directory is on the writable MicroSD partition.
- [x] SSH host keys are generated successfully.
- [x] SSH accepts the configured authorized key.
- [x] The SSH ED25519 fingerprint remains unchanged across reboot.
- [x] Reconnecting after reboot does not require removing the known-host entry.

Hardware evidence:

- Firmware name: `resist-dinner`
- Firmware UUID: `c149d1e5-bf31-5c48-de49-9d31e0925d32`
- The ED25519 fingerprint before reboot was
  `SHA256:FV/R0bGaCv9BMqCaBTTk3QYi+fMxXsZP5dv/sFXdMuc`.
- The ED25519 fingerprint after reboot was identical.
- SSH opened an IEx session after reboot without replacing the known-host entry.

### Milestone 12: Evaluate remaining Nerves conventions

Implementation status: evaluated on July 18, 2026.

The remaining dependency and virtual-machine conventions were reviewed after
the runtime behavior had been hardware-verified.

#### Nerves Pack

Do not adopt `nerves_pack`.

The example application already declares and configures the individual runtime
services it needs. Its Atom Cam 2 integration also requires explicit Wi-Fi,
discovery, SSH persistence, firmware metadata, and time configuration.

Adopting the dependency bundle would obscure those requirements and introduce
direct-link networking dependencies that the Wi-Fi-client-only device does not
use.

#### Direct dependencies

Retain the current direct dependencies.

Each runtime dependency is either called by application code, configured
directly, or provides behavior verified during an earlier milestone. No
dependency became redundant when the custom network worker was removed.

Obsolete commented dependency declarations were removed from `mix.exs`.

#### Virtual-machine arguments

Preserve the current `rel/vm.args.eex`.

The release deliberately names the node on `127.0.0.1` and binds Erlang
distribution to the loopback interface. Remote administration uses NervesSSH
rather than raw distributed Erlang.

The configuration has been verified with the current Elixir and OTP versions.
Migrating node naming and cookie configuration to release environment variables
would not improve current behavior and would introduce avoidable risk.

Verification:

- [x] Review the services and dependencies provided by `nerves_pack`.
- [x] Confirm direct-link and DHCP-server behavior is not required.
- [x] Confirm every current direct dependency has a project-level consumer.
- [x] Confirm no dependency became redundant after removing the network worker.
- [x] Remove obsolete commented dependency declarations.
- [x] Review the node name, cookie, distribution interface, and shell settings.
- [x] Confirm Erlang distribution remains restricted to loopback.
- [x] Preserve the hardware-verified VM configuration.

