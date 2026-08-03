# Changelog

## Unreleased

- Start the native camera stack automatically at boot. The new
  `CameraNative` GenServer loads the camera kernel modules, then runs
  `camd` (libimp capture + H.264 encode into v4l2loopback) and
  `v4l2rtspserver` under MuonTrap supervision with restart on exit. The
  stream is published at `rtsp://<ip>:8554/video0_unicast`. `camd` still
  lives on `/data` until it is packaged into the system; startup waits
  for it. Opt out with `enabled=false` in
  `/data/atomcam2-native-camera/auto-start.conf` (a missing file means
  enabled — native is the only camera mode in this deployment).

- Announce readiness at boot. When the application starts, the camera says
  「起動しました。」 through the speaker and blinks the blue status LED
  three times, leaving it lit. This assumes native-only operation (no
  `iCamera_app`, which would hold the IMPAudio lock): the
  `atomcam2-boot-announce` script loads the audio kernel modules itself
  when nothing loaded them yet. Playback uses a new `atomcam2-aoplay`
  tool (libimp `IMP_AO`, prebuilt with the vendor uClibc toolchain;
  source under `package/atomcam2-boot-announce/`). Disable with
  `ATOMCAM2_BOOT_ANNOUNCE=disabled` or swap the PCM via
  `ATOMCAM2_BOOT_ANNOUNCE_SOUND` in `atomcam2.env` on the MicroSD.

## 0.4.0 - 2026-08-03

- Support multiple Wi-Fi locations. `nerves-provisioning.conf` now accepts
  numbered SSID/passphrase pairs (`NERVES_WIFI_SSID_2`, ...) in addition to
  the unnumbered pair, and VintageNet connects to whichever configured
  network is in range. The same MicroSD works across locations without a
  rebuild — edit the FAT partition to add one. An empty passphrase configures
  an open network.

- Support wired-only deployments in the vendor camera integration. Readiness,
  the precheck network check, and the IPv4 address the runtime reports now
  accept eth0, not just wlan0, so a camera reached over USB Ethernet with no
  Wi-Fi association still starts. Time sync likewise triggers on the overall
  connection rather than wlan0 specifically.

- Add optional RTSP publishing of the vendor camera's already-encoded video.
  A preloaded frame hook mirrors the encoder output into a v4l2loopback
  device, which `v4l2rtspserver` publishes without re-encoding. Enable it by
  writing `enabled=true` to `/data/atomcam2-rtsp/auto-start.conf`; the
  server follows the vendor camera runtime and stops when it does.
- Load `v4l2loopback` from `atomcam2-pre-run` so the devices exist before the
  vendor runtime starts. `ATOMCAM2_VIDEO_LOOPBACK_DEVICES` and
  `ATOMCAM2_VIDEO_LOOPBACK_VIDEO_NR` select how many nodes are created and
  which numbers they take.
- Patch v4l2loopback to honour a caller-supplied `sizeimage` for compressed
  formats. It previously derived the buffer from raw geometry, reserving
  7.91 MiB per buffer at 1080p for a stream whose frames are a fraction of
  that, and `v4l2rtspserver` propagates that size into live555's
  `OutPacketBuffer::maxSize`. On an 87 MiB board this exhausted memory as
  soon as a server attached. Verified on hardware: 1920x1080 H.264 at
  ~18 fps and ~950 kbps alongside the vendor runtime.
- Report loopback device availability from `atomcam2-vendor-camera precheck`.
- Make an RTSP frame stall observable. The frame hook rewrites a heartbeat
  file each forwarded frame, and `RtspServer` warns through the log and its
  `status` when the heartbeat stops advancing while everything still reports
  "running" — the stall that self-recovers on HD contention and the one that
  needs a reboot are otherwise indistinguishable from the process list. This
  observes rather than recovers: restarting the server reconnects to a
  frameless loopback, the vendor runtime cannot restart without a reboot, and
  a reboot on frame-absence would evict a mobile app legitimately viewing HD.

- Add wired LAN support through USB Ethernet adapters. The control kernel now
  builds the `r8152`, `usbnet`, `asix`, `ax88179_178a`, `cdc_ether`, and
  `rndis_host` modules, matching the driver set proven by atomcam_tools.
- Add `atomcam2-eth-driver`, invoked from `atomcam2-pre-run` before the Wi-Fi
  driver, which probes the class and vendor drivers in order and reports
  progress to `atomcam2-eth-driver.env` on the FAT partition. Disable it with
  `ATOMCAM2_PRE_RUN_ETH_DRIVER=0`.
- Report `eth0` presence and address in the pre-run and network-check
  breadcrumb files.
- Configure `eth0` with DHCP in the example application through
  `vintage_net_ethernet`. VintageNet prefers the wired route and falls back to
  Wi-Fi when the cable or adapter is absent.
- Keep shipping the verified vendor-compatible control kernel unchanged. The
  Buildroot kernel build exists to produce loadable modules whose vermagic
  matches it, so `mix upload` alone enables wired networking. Verified on
  hardware with a Realtek RTL8152 adapter (`0bda:8152`).

## 0.3.0 - 2026-07-28

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
- Add explicit `/data` opt-in for camera startup after firmware validation,
  Internet connectivity, synchronized time, and the existing compatibility
  precheck.
- Limit automatic camera startup to one attempt per boot and report later
  degradation without rebooting or entering an automatic restart loop.
- Normalize stale vendor runtime markers after reboot and verify opt-in camera
  startup, firmware validation, watchdog ownership, Wi-Fi/SSH stability, and
  recording finalization across candidate and ordinary reboots.
- Preserve unexported local recordings above the spool target and evict only
  files with size-matching persistent completion markers.
- Confine the SFTP account root, limit each normal export cycle to two files,
  bound individual OTP SSH/SFTP operations, and reuse one supervised session
  across polls.
- Check an existing ext2 `/data` filesystem offline before mounting it
  read-write so an unclean power cycle is repaired before application access.
- Validate atomic NAS publication, idempotent retry, outage recovery,
  selective 20-day retention, spool safety, persistent-session cleanup, and
  sustained camera reachability against a confined LMDE 7 endpoint.

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
