# Changelog

## 0.1.0-dev

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
