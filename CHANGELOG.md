# Changelog

## Unreleased

- Add ADR 0008 and a read-only `atomcam2-vendor-camera precheck` for the
  optional vendor camera compatibility investigation.
- Enable the minimal BusyBox `chroot` applet required to run the vendor uClibc
  runtime without replacing the Nerves musl userspace.
- Record the protected-filesystem, module ABI, memory, watchdog, and NAS
  filesystem findings from the physical v0.2.0 feasibility probe.
- Add explicit `prepare`, `start`, `status`, and `stop` commands for a manual,
  disabled-by-default vendor camera compatibility runtime.
- Keep protected vendor filesystems read-only, place private configuration and
  spool state under `/data`, expose only selected devices, and drop vendor
  process capabilities for networking, mounting, module loading, reboot, and
  device-node creation.
- Add a narrow freestanding compatibility shim so required vendor assistant,
  network-status, and SD-card checks succeed without exposing the real
  watchdog, Wi-Fi control, or MicroSD block device.
- Verify vendor network, cloud, SD health, and SD mount initialization, bounded
  memory use, descendant/process/mount/IPC shutdown, permanent-module reboot
  recovery, stable Nerves Wi-Fi and watchdog ownership, and firmware validation
  on physical hardware.
- Verify the standard Atom mobile application, HD live view, recorded playback,
  healthy storage reporting, and finalized one-minute continuous recordings
  under the `/data` spool.
- Add an opt-in OTP SFTP exporter for finalized recordings after confirming
  that the protected control kernel cannot mount NFS or CIFS.
- Require key authentication and a provisioned NAS host key, publish through a
  temporary name and atomic rename, retry idempotently, preserve a bounded
  local playback spool, and remove dated NAS recordings after the configured
  retention period.

## 0.2.0 - 2026-07-26

- Adopt standard fwup media creation and `mix burn` workflows while preserving
  the verified Atom Cam 2 control kernel and flat-SD boot contract.
- Add a persistent `/data` partition with format-if-missing initialization,
  repair checks, and factory-reset support.
- Add an immutable boot manager, redundant firmware metadata, A/B application
  slots, health-based confirmation, watchdog recovery, and rollback.
- Integrate standard Nerves firmware status, validation, revert,
  `prevent-revert`, and factory-reset APIs.
- Support standard SSH `mix upload` through the checked Atom Cam 2 A/B updater,
  including interrupted-transfer cleanup and progress reporting.
- Align firmware authentication with the ordinary Nerves baseline: SSH
  authorizes update access, fwup and target checks validate the candidate, and
  publisher signatures remain optional.
- Require a complete removable-media installation when moving from v0.1.0 to
  the new A/B layout.

## 0.1.0 - 2026-07-18

- Add publishable system and Atom Cam 2 custom toolchain artifact metadata.
- Move the Linux 3.10 VintageNet compatibility definition into system staging headers.
- Make the example application use released artifacts by default with an explicit local-system override.
- Add a release script for artifact creation, publication, and isolated application verification.
- Reject unverified remote fwup updates and retain `mix atomcam2.install` as the supported update path.
- Create minimal AtomCam2 Nerves system source snapshot.
- Focus first milestone on `ping nerves.local` and `ssh nerves.local`.
- Add flat SD-card packaging scripts.
- Add minimal example Nerves app for Wi-Fi, mDNS, and SSH.
- Keep first-SSH shell helpers in `rootfs_overlay` instead of duplicating them through a Buildroot package.
- Harden SD payload script option parsing and hostname validation.
- Harden SD install/report scripts so missing option values fail clearly.
- Fall back to `nerves` when the target-side hostname file is missing or invalid.
- Treat a missing Wi-Fi passphrase as an open-network configuration instead of `nil`.
- Remove hidden target-side dependencies on BusyBox `head`, `sort`, and `tr`.
- Let SD packaging reuse an existing generated `nerves-provisioning.conf` when present.
- Tighten hostname validation and refuse dangerous SD packaging/install directory combinations.
- Resolve host-side directory paths physically before comparing safety-sensitive source, output, and mount directories.
- Create the host `opt/ext-toolchain/bin` directory expected by `nerves-config` when using the current internal Buildroot toolchain.
- Remove the stale `atomcam2-first-ssh` Buildroot package directory now that helper scripts are installed through `rootfs_overlay`.
- Defer camera, RTSP, WebUI, Samba, and vendor runtime integration.
