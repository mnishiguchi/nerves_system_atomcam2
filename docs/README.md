# Project documents

## ADR

Architecture Decision Records are stored in `adr/`.

Use ADRs for decisions that should remain true beyond a particular build or hardware test.

The optional vendor camera compatibility design is accepted in:

- [`adr/0008-run-vendor-camera-runtime-as-optional-compatibility-service.md`](adr/0008-run-vendor-camera-runtime-as-optional-compatibility-service.md)

## Worklog

Dated development notes, build attempts, hardware tests, and troubleshooting records are stored in `worklog/`.

Worklogs are historical records. Earlier documents may describe an intermediate boundary that was resolved later. When conclusions differ, prefer the newest worklog with confirmed hardware evidence.

## First network milestone

The first Atom Cam 2 milestone was completed on July 15, 2026:

```sh
ping nerves.local
ssh nerves@nerves.local
```

The authoritative result and confirmed blockers are documented in:

- [`worklog/20260715-atomcam2-ping-ssh-bringup.md`](worklog/20260715-atomcam2-ping-ssh-bringup.md)

Supporting investigations are retained separately:

- [`worklog/20260713-atomcam2-toolchain-dsp-ase-investigation.md`](worklog/20260713-atomcam2-toolchain-dsp-ase-investigation.md)
- [`worklog/20260714-first-ping-ssh-wifi-and-boot-investigation.md`](worklog/20260714-first-ping-ssh-wifi-and-boot-investigation.md)
- [`worklog/20260714-sdio-wifi-driver-bring-up.md`](worklog/20260714-sdio-wifi-driver-bring-up.md)

Camera runtime, RTSP, WebUI, Samba, firmware updates, and production hardening remain outside that milestone.

## Vendor camera compatibility

The read-only v0.2.0 hardware investigation and the subsequent manual-runtime
trial are recorded in:

- [`worklog/20260726-adr-0008-vendor-camera-feasibility.md`](worklog/20260726-adr-0008-vendor-camera-feasibility.md)
- [`worklog/20260726-adr-0008-vendor-camera-manual-runtime.md`](worklog/20260726-adr-0008-vendor-camera-manual-runtime.md)
- [`worklog/20260726-adr-0008-mobile-and-storage-compatibility.md`](worklog/20260726-adr-0008-mobile-and-storage-compatibility.md)

The corrected manual runtime keeps Nerves ownership boundaries intact and
passes vendor network, cloud, SD health, mobile live-view, recorded-playback,
storage-screen, and one-minute local-recording checks. Phase 2 and Phase 3 are
complete; NAS export and retention remain Phase 4.
