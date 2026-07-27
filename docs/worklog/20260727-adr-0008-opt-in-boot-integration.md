# ADR 0008 Phase 5: opt-in boot integration

Date: July 27, 2026

## Scope

Start the already validated vendor camera compatibility runtime after boot
without weakening Nerves firmware validation, networking, timekeeping,
watchdog, OTA, or rollback behavior.

## Implemented policy

`Atomcam2NervesApp.VendorCamera` is supervised on the Atom Cam 2 target. It
remains dormant unless:

```text
/data/atomcam2-vendor-camera/auto-start.conf
```

contains `enabled=true`. Missing, disabled, or malformed configuration cannot
start the vendor runtime.

An enabled worker waits for:

- validated firmware;
- an Internet connection on `wlan0`;
- synchronized system time; and
- the existing compatibility precheck.

It invokes only `atomcam2-vendor-camera precheck` and
`atomcam2-vendor-camera start`, verifies `result=running`, and makes at most one
automatic start attempt per boot. Later degradation remains visible to the
operator without an automatic restart or reboot loop.

## Reboot-state correction

Power cycling the Phase 4 firmware exposed a stale-state boundary. The
persistent runtime marker still said `running`, while its recorded boot ID
belonged to the prior boot and all vendor processes were stopped. `status`
therefore reported `result=degraded`, which correctly left the mobile
application offline but would also have blocked automatic startup.

Status reporting now treats all transient lifecycle states from a different
boot as `prepared`, matching the cleanup already performed by `start`. It does
not hide a same-boot failure or mutate persistent state during a status check.

## Target command-runner correction

The first Phase 5 candidate used `MuonTrap.cmd/3`. Its port helper exited with
`:epipe` on the protected Linux 3.10 target whenever the worker checked camera
status. Repeated worker restarts reached the supervisor restart limit and
stopped only the example application. Nerves SSH, networking, watchdog, and
the unvalidated candidate remained reachable.

The candidate was recovered by temporarily setting `enabled=false`, restarting
the application, and allowing the normal firmware-health checks to validate
it. All health gates passed.

The worker now uses the standard `System.cmd/3` path already proven by the
firmware-health and manual camera flows. This removes the incompatible helper
without adding another service or dependency.

## Initial corrected-firmware acceptance

The first firmware with the target-compatible command path was:

```text
UUID: 1d0ce1ad-c228-5764-2327-c7d7d2536017
slot: B
validation: validated
```

On its first candidate boot, the enabled worker initially reported:

```text
phase=waiting
start_attempts=0
waiting=validated_firmware,synchronized_time
```

After firmware validation and time synchronization, it reported:

```text
phase=running
start_attempts=1
last_result=started
```

The compatibility status confirmed:

```text
process=iCamera_app state=running
storage_isolation=shim_active
process=hl_client state=running
process=assis state=running
watchdog_isolation=shim_active
private_watchdog_view=absent
result=running
```

Nerves `heart` remained the owner of `/dev/watchdog0`. Wi-Fi reported
`:internet`, Nerves time reported synchronized, the application remained
started, and a new one-minute MP4 finalized at:

```text
/data/atomcam2-vendor-camera/spool/record/20260727/17/25.mp4
bytes=4418336
```

## Persistence reboot

A deliberate ordinary reboot then verified the persistent boundary. Before
startup:

- the same firmware remained validated in slot B;
- `enabled=true` remained under `/data`;
- stale prior-boot runtime state reported `prepared`;
- the camera processes were stopped;
- the worker waited only for synchronized time; and
- `start_attempts` remained zero.

After synchronization, the worker again reached `phase=running` with exactly
one attempt. All three vendor processes and both isolation shims were healthy,
Nerves retained the watchdog, and a post-reboot segment finalized:

```text
/data/atomcam2-vendor-camera/spool/record/20260727/17/28.mp4
bytes=3580569
```

The running device answered 30 of 30 pings with no packet loss.

## Final candidate and data-filesystem repair

The final polish made configuration parsing strictly accept only the enabled or
disabled line, extended status-call tolerance across the bounded startup
sequence, and contained command-process exits inside the worker. Host coverage
increased to 38 passing tests.

The first upload of that final build did not complete while the vendor runtime
was active. The target had no remaining installer process or update lock, but
the interrupted attempt left updater-owned temporary paths. Removing the
orphan exposed an ext2 directory-entry error:

```text
ext2_lookup: deleted inode referenced: 155047
```

Ordinary `/data` writes still passed. The vendor runtime and example
application were stopped, `/data` was unmounted, and the established ADR 0005
repair command ran:

```text
e2fsck -p -f /dev/rootdisk0p4
```

It returned status 1 and repaired two inode block counts plus the orphaned
updater entry. A second offline `e2fsck -f -n` returned status 0. `/data`
remounted read-write, and the exact updater staging and work directories were
empty.

With the camera workload stopped, the same final bundle installed normally:

```text
UUID: ba2a02ba-e525-5f86-cf35-40343d3f1ff5
slot: A
validation: validated
SHA-256: 4a290ce8d19e96da27cb95dc09906a87721996cf0a5e32dfac04c7b20bff7748
```

The exact final candidate repeated the readiness-gated automatic startup with
`start_attempts=1`, all vendor processes and isolation checks healthy, Nerves
watchdog ownership intact, and both updater directories empty. It answered 30
of 30 pings and finalized:

```text
/data/atomcam2-vendor-camera/spool/record/20260727/17/58.mp4
bytes=4833565
```

## Remaining operator acceptance

The automated and physical target boundaries pass. Final standard-mobile-app
live-view confirmation after the persistence reboot is an operator check; it
does not require another firmware change.
