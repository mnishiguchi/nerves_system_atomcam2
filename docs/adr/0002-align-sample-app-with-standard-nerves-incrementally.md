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
- [ ] Add NervesMOTD without changing application supervision or networking.
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
