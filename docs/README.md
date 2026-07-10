# Project documents

## ADR

Architecture Decision Records are stored in `adr/`.

Use ADRs for decisions that should remain true beyond the current build attempt.

## Worklog

Development notes, build attempts, hardware test notes, and troubleshooting records are stored in `worklog/`.

Current first milestone:

```sh
ping nerves.local
ssh nerves.local
```

The first milestone is intentionally limited to building and booting a minimal Atom Cam 2 Nerves system that becomes reachable over Wi-Fi. Camera runtime, RTSP, WebUI, Samba, and vendor application compatibility are deferred.
