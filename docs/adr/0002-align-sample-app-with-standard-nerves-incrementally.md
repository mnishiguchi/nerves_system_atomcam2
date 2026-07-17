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
- [ ] Activate RingLogger on the target.
- [ ] Advertise standard SSH-related mDNS services.
- [ ] Advertise Nerves device metadata.
- [ ] Evaluate the mDNS DNS bridge.
- [ ] Add runtime Wi-Fi credentials without removing existing sources.
- [ ] Evaluate `nerves_pack` before adopting it.
- [ ] Remove dependencies made redundant by verified replacements.
- [ ] Simplify custom Wi-Fi supervision only after replacement behavior is verified.
- [ ] Review VM argument conventions independently.
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

The custom Atom Cam 2 SD boot path does not expose the usual active firmware KV
metadata. The advertisement therefore uses runtime and application values that
remain available:

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

