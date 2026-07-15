# Project documents

## ADR

Architecture Decision Records are stored in `adr/`.

Use ADRs for decisions that should remain true beyond a particular build or hardware test.

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
