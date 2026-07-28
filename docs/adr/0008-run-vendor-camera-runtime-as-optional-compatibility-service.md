# ADR 0008: Run the vendor camera runtime as an optional compatibility service

## Status

Accepted on July 26, 2026

The read-only feasibility gate and Phase 2 are complete. On July 27, 2026, the
operator confirmed the standard mobile application, HD live view, recorded
playback, and a healthy storage screen. The corrected runtime reaches healthy
vendor network, cloud, and storage state while Nerves retains its ownership
boundaries.

Phase 3 local continuous recording is also complete: finalized one-minute MP4
segments appear under the `/data` spool, while the active segment remains in
private tmpfs.

Phase 4 implementation is in progress. The protected kernel cannot mount NFS
or CIFS, so the first exporter uses the OTP SFTP client already present in the
firmware and leaves the kernel contract unchanged. Configuration parsing,
completed-file selection, idempotent publication, local spool bounds, and
date-based retention have host coverage. A physical Atom Cam 2 also passed
SFTP upload, checksum, atomic-publication, idempotency, selective-retention,
and connection-failure recovery trials against a disposable endpoint. The
intended confined SFTP account also passes authentication, confinement, and
atomic publication. A clean production trial exposed an OTP SSH/SFTP call that
did not return after its internal timeout. Each operation now has an additional
hard per-call deadline and explicit channel and connection cleanup. Two
production cycles subsequently published four files, preserved stable camera
reachability, and left no client or server SSH sessions. The final
whole-transfer-deadline removal repeated the result with two more files. A
sustained spool-pressure/retention run remains before Phase 4 is complete.

Phase 5 is complete. The application has an opt-in boot worker that waits for
validated firmware, Internet connectivity, synchronized time, and a successful
compatibility precheck. Candidate and ordinary-reboot trials pass persistent
opt-in, stale-state recovery, one automatic start attempt, healthy vendor
processes, watchdog ownership, Wi-Fi/SSH stability, and post-reboot recording.
Later degradation remains visible without stopping Nerves, rebooting, or
attempting an automatic process restart.

The Phase 5 target evidence is recorded in
[`../worklog/20260727-adr-0008-opt-in-boot-integration.md`](../worklog/20260727-adr-0008-opt-in-boot-integration.md).

## Context

The v0.2.0 system provides the ordinary Nerves application workflow, persistent
`/data`, A/B firmware updates, rollback, Wi-Fi, SSH, timekeeping, and a hardware
watchdog. It deliberately does not run the Atom Cam 2 vendor camera
application.

The next product goal is narrower than adopting the complete `atomcam_tools`
environment:

- preserve live viewing through the standard Atom mobile application;
- produce continuous one-minute recordings locally;
- export completed recordings to a NAS; and
- retain NAS recordings for a configurable period, initially about 20 days.

The vendor camera application and its libraries use a uClibc MIPS userspace,
while Nerves uses musl. The vendor application also expects fixed paths such as
`/system`, `/configs`, `/tmp`, and `/media/mmc`, loads camera-specific kernel
modules, uses System V IPC, and starts helper processes.

The protected v0.2.0 control kernel already exposes the vendor root, application,
and configuration filesystems under `/atom`. A physical-device feasibility
probe found that:

- `/atom`, `/atom/system`, and `/atom/configs` are mounted read-only;
- the camera, ISP, audio, and VPU modules match the running kernel release;
- the vendor executables and their uClibc libraries are present;
- the camera's reserved 36 MiB memory region is present;
- `/data` provides a large writable ext2 filesystem;
- Nerves `heart` owns `/dev/watchdog0`;
- the vendor `assis` process also opens and controls the hardware watchdog; and
- the protected kernel does not currently expose NFS or CIFS client support.

The stock vendor startup script is not a safe integration point. In addition to
camera initialization, it starts its own Wi-Fi flow, writes hardware registers,
loads unrelated drivers, starts factory and USB helpers, and starts the
watchdog-owning `assis` process.

The evidence is recorded in
[`../worklog/20260726-adr-0008-vendor-camera-feasibility.md`](../worklog/20260726-adr-0008-vendor-camera-feasibility.md).

A subsequent mobile failure and corrected physical trial established that:

- `assis`, `hl_client`, and `iCamera_app` are all required for the vendor
  mobile/cloud path;
- a narrow preload shim lets `assis` run without opening the hardware watchdog;
- the vendor network flow can consume Nerves connection state without changing
  the interface, DHCP client, supplicant, or DNS ownership;
- the vendor SD checks can use a regular-file placeholder and the `/data` spool
  without seeing the real MicroSD block device;
- vendor network, cloud, SD health, and SD mount initialization complete;
- Nerves `heart` retains sole hardware-watchdog ownership;
- the vendor-requested GC2053 sensor interface is `data_interface=1`;
- the three primary vendor processes use about 23 MiB combined RSS in the
  corrected trial;
- Nerves Wi-Fi, SSH, firmware validation, and recovery remain healthy; and
- stop cleans primary processes, vendor descendants, mounts, and IPC, while a
  reboot remains required to remove the permanent camera modules.

That evidence is recorded in
[`../worklog/20260726-adr-0008-mobile-and-storage-compatibility.md`](../worklog/20260726-adr-0008-mobile-and-storage-compatibility.md).

## Decision

Add an optional vendor camera compatibility service, disabled by default.

Do not import the complete `atomcam_tools` root filesystem, service manager,
network stack, web UI, update flow, Samba server, or NAS implementation.

### Ownership

Nerves owns:

- boot, OTA update, rollback, recovery, and the hardware watchdog;
- Wi-Fi, DHCP, DNS, mDNS, SSH, and time synchronization;
- mounting and unmounting the compatibility environment;
- starting, supervising, and stopping vendor processes;
- writable configuration and recording state under `/data`; and
- NAS transfer, retry, publication, spool limits, and retention.

The vendor runtime owns only:

- the camera, ISP, audio, and encoder drivers required for capture;
- vendor camera processes needed for the standard mobile application;
- encoding and finalization of local recording segments; and
- the vendor protocol behavior required by the mobile application.

The service must not hand boot, networking, watchdog, update, or reboot policy
to vendor processes.

### Vendor filesystems and writable state

Keep the protected vendor root and application filesystems read-only. Keep the
original internal configuration partition mounted read-only as the source of
factory identity, calibration, pairing, and application configuration.

Before the first manual start, copy the required configuration into:

```text
/data/atomcam2-vendor-camera/configs
```

Protect that directory as device-private state. Do not print configuration
contents or copy them into build artifacts, reports, logs, or Git.

Overmount the private copy at `/atom/configs` only inside the compatibility
layout. Stopping the service must reveal the original read-only mount again.
The service must never remount an internal MTD partition read-write.

Keep transient vendor state in a size-bounded private tmpfs. Store durable
service configuration, the recording spool, and minimal runtime metadata below:

```text
/data/atomcam2-vendor-camera
```

### Compatibility isolation

Run the vendor uClibc processes in a `chroot` rooted at `/atom`. This is a
compatibility boundary for paths and libraries, not a security sandbox.

Bind or mount only the resources the camera runtime needs. In particular:

- expose the camera device nodes created by the selected modules;
- expose procfs and the required sysfs paths;
- provide a private writable tmpfs for `/tmp`;
- map the private configuration copy to `/configs`;
- map the local recording spool to the vendor media path; and
- replace or hide vendor commands that can restart Wi-Fi, modify flash, reboot
  the device, or claim the real watchdog.

Do not run the stock `app_init.sh`. Define and test a minimal ordered module and
process list instead. Do not load the vendor Wi-Fi, exFAT, USB Ethernet,
factory-test, or firmware-update components.

The compatibility service must not disable Nerves `heart` or release its
hardware-watchdog ownership. `assis` is required, so a small freestanding shim
implements only its four watchdog calls and leaves the real watchdog absent
from the private device view. The same shim acknowledges only the already
established `/dev/mmcblk0p1` to `/media/mmc` compatibility mapping. Importing
the broad `atomcam_tools` preload layer is not part of this decision.

The fake `/dev/mmcblk0p1` must remain a verified regular file on the bounded
private device tmpfs, and the vendor process must not receive `CAP_MKNOD`. The
real Nerves MicroSD block device must never be exposed to the vendor runtime.
Vendor `tf_prepare`, `blkid`, Wi-Fi, DHCP, supplicant, DNS, and mount
expectations may be emulated only where Nerves already owns the corresponding
resource.

### Mobile-application compatibility

Mobile live viewing is an acceptance criterion, not an assumption. The initial
manual trial must verify that the existing device identity and pairing state are
sufficient when Nerves continues to own Wi-Fi.

The service must not report success merely because `iCamera_app` stays alive.
Success requires:

- live viewing from the standard Atom application;
- stable Nerves Wi-Fi and SSH;
- continued Nerves hardware-watchdog ownership;
- healthy Nerves firmware validation state; and
- a clean, bounded stop sequence.

The July 27 physical acceptance passed all five requirements. The already-paired
application showed the camera online, opened HD live view, played recorded
footage, and showed continuous local recording without the earlier SD-card
error.

### Recording boundary

The vendor runtime may create and finalize one-minute MP4 segments in a local
spool below `/data`. Incomplete files and completed files awaiting export must
have separate paths or an equally explicit state transition.

Use the smallest confirmed completion hook. `atomcam_tools` intercepts the
vendor move of a finished recording from `/tmp` into `/media/mmc/record`; that
behavior is useful evidence, but its combined CIFS, webhook, scheduling, and
path-rewrite scripts are not adopted.

The physical runtime confirms that no additional hook is needed. The vendor
application writes the active minute under private `/tmp` and moves each
finalized MP4 into `/media/mmc/record`, which is already the `/data` spool.

The vendor runtime must not mount or write to the NAS directly.

### NAS export and retention

A separate Nerves-supervised exporter owns NAS delivery. It must:

- consume only completed local segments;
- retry after network and NAS outages;
- copy to a temporary destination name and rename atomically after completion;
- make repeated attempts idempotent;
- keep the local spool near a configured target without deleting unexported
  recordings; and
- remove NAS recordings older than the configured retention period.

NFS was evaluated first. The protected v0.2.0 kernel registers neither NFS nor
CIFS, and the shipped kernel is intentionally fixed and verified. Do not
replace it or import vendor SMB code for NAS recording.

Use OTP SFTP as the first supported transport. It is already present in the
firmware, needs no additional daemon or filesystem client, and keeps NAS
failures outside the camera runtime. Require key authentication and a
pre-provisioned `known_hosts` entry; do not accept unknown host keys or store a
NAS password in the configuration.

Mirror the vendor's `YYYYMMDD/HH/MM.mp4` path below one configured remote
directory. Upload to `MM.mp4.uploading`, verify its size, and rename it to the
final path. Treat an existing final path as the same upload only when its size
matches. Otherwise report a conflict and leave the local segment for operator
review.

The configured remote directory may be `.` when the SFTP server starts the
account inside a dedicated, confined recording directory. Reject `/`, parent
traversal, and embedded current-directory components.

Keep successfully exported files in the local spool for recent mobile-app
playback. Record export completion outside the vendor-visible spool and remove
the oldest successfully exported local segments only when the configured spool
limit is exceeded. An outage may temporarily grow the spool past that target;
never enforce it by deleting an unexported segment. Retention may delete only
recognized recording names below date directories older than the configured
period.

Do not rely solely on OTP SSH/SFTP's internal operation timeouts. Bound each
blocking operation independently. The process that owns the channel and
connection must unwind through explicit cleanup after an error or timeout; do
not impose a whole-transfer kill that can bypass cleanup. A timeout must write
no completion marker and must never make a local segment eligible for removal.
A final file published immediately before a timeout remains safe: the next
attempt verifies its size and treats it as already present. A partial temporary
file is removed and retried.

### Boot, failure, and recovery behavior

Automatic startup may be enabled only by
`/data/atomcam2-vendor-camera/auto-start.conf` containing exactly
`enabled=true`. Missing, disabled, or malformed configuration must never start
the vendor runtime. Startup waits for:

- `/data` mounted read-write;
- Nerves networking healthy;
- synchronized or otherwise trustworthy system time; and
- a successful compatibility precheck.

Firmware must also be validated before automatic camera startup so the
compatibility runtime cannot interfere with rollback confirmation.

The supervisor makes at most one automatic start attempt per boot and keeps
visible failure state. It does not automatically stop or restart a degraded
runtime because the selected modules are permanent in the protected kernel and
a clean stop requires a deliberate reboot before another start. It must not
create a reboot loop or restart Nerves networking. Manual stop still terminates
only the vendor processes and removes only compatibility mounts and IPC.

A vendor runtime failure must leave Nerves, SSH, OTA, rollback, and recovery
usable. A NAS outage must affect only export and local spool pressure, never
camera boot or firmware health.

All persistent compatibility state remains in `/data` across OTA update and
rollback. Firmware must ignore state versions it does not understand rather
than migrating them irreversibly during boot.

## Implementation status

The read-only probe establishes a conditional go:

- vendor files, modules, libraries, storage, reserved memory, and IPC support
  are present;
- a chroot compatibility layout is technically viable; and
- protected flash can remain read-only by using a private configuration copy.

It does not authorize starting the stock runtime. The Phase 2 implementation
instead provides an explicit minimal runtime:

```sh
atomcam2-vendor-camera precheck
atomcam2-vendor-camera prepare
atomcam2-vendor-camera start
atomcam2-vendor-camera status
atomcam2-vendor-camera stop
```

`prepare` creates the private configuration and spool state. `start` uses an
explicit module list and launches `assis`, `hl_client`, and `iCamera_app` in
stock order. The compatibility environment omits the real watchdog and real SD
block device, hides or replaces commands that can alter networking, flash,
mounts, modules, or power state, and removes the corresponding capability
classes from the vendor processes.

The corrected physical trial resolved the watchdog conflict, vendor networking
crash, SD-card error, process cleanup, memory measurement, private
configuration behavior, and reboot recovery. Vendor initialization reaches
network-connected, cloud-initialized, SD-health-success, and SD-mount-success
state. Mobile live view, playback, storage status, and one-minute local
recording passed on July 27. The runtime remains disabled by default.

The Phase 4 application implementation adds a supervised exporter that remains
inert unless `/data/atomcam2-vendor-camera/nas-export.conf` explicitly enables
it. The configuration is strict, contains no password, and points OTP SSH at a
device-private key and `known_hosts` directory. Each run handles at most two
new segments, then waits at least 60 seconds before retrying. One slot matches
the recording cadence and one drains the backlog, while leaving CPU time for
the camera and core Nerves services. Completion markers are specific to the
configured endpoint and must be rotated when that endpoint changes. Host tests
cover config validation, completed-file filtering, symlink rejection, bounded
spool eviction of successfully exported files, preservation of unexported
files, persistent completion markers, compact-date retention decisions, and a
transport call that never returns.
Firmware `acb7f0a2-1189-505d-8ea5-7c82b71c03a5` additionally passed a physical
device-to-SFTP trial. A 3,556,322-byte MP4 published without a leftover
temporary file and matched SHA-256 at both ends; a repeated attempt was
idempotent. Retention removed only recognized old recording names, and a
refused connection preserved the local file before successful recovery. The
production NAS later accepted 20 files while preserving every local source.
After an inconclusive reachability loss, firmware
`174c476f-9489-50c2-548c-4b62df277f9f` reduced the batch to two files per
minute. A later clean production run reproduced the reachability loss without
the earlier console-output confounder. Persisted diagnostics showed stable
Erlang memory but an exporter process permanently waiting in `gen:do_call`;
the workstation accepted 12 complete SFTP sessions and saw no thirteenth
connection. Firmware `8b3465d1-b8b8-5914-aa36-6c3e8e1c0cdd` therefore adds
an independent 30-second transport deadline. Follow-up review found that
killing the whole transport owner could bypass its SFTP cleanup, so firmware
`eafb221d-e366-5cd1-4f2c-42ee129d9c10` (`trigger-yard`) instead bounds each
OTP operation and explicitly stops the channel and connection. A
connection-refused trial returned promptly without a leaked client. Two
enabled production cycles then published four files atomically while camera
reachability remained stable; disabling the exporter left `:sshc_sup` empty,
and the server had no remaining per-session `sshd` process. Final firmware
`efc08024-9abe-5a5d-6d68-be70ce82b5bc` (`uncover-skill`) removed the
whole-transfer deadline, validated in slot A, and repeated a two-file
production cycle. It passed 87 of 87 pings, retained all unexported recordings,
and again left no client or server SSH session. A subsequent ten-minute
production run completed 11 SFTP sessions with 11 matching server-side closes
and 614 of 614 ping replies. Target diagnostics remained bounded and showed no
persistent SSH client.

That run also exposed two completion-marker entries damaged by the preceding
forced power cycle. Remote files had been published, both local MP4s remained,
and marker writes failed closed with `:eio`; no unmarked source became eligible
for deletion. Offline `e2fsck` repaired the two entries and related metadata,
and a second full check returned clean. ADR 0005 now checks ext2 offline before
the first read-write mount because mount success alone does not detect this
class of directory damage. Long-running backlog, retention, and mobile-app
acceptance remain. Firmware `b9aa5131-115a-592a-3437-b4495ac8d513`
(`pig-oil`) physically validates the clean-filesystem path: preen completed in
approximately 132 milliseconds, `/data` remounted read-write, and the candidate
validated with the vendor runtime, Nerves watchdog, and local recording
healthy. A physical power interruption then exercised the unclean path: preen
returned status 1 after repairing the filesystem, `/data` remounted without a
kernel filesystem error, and the operator confirmed ping, SSH, and mobile live
view on that first boot.

The Phase 5 application implementation adds
`Atomcam2NervesApp.VendorCamera`. Missing configuration leaves it dormant.
When enabled, it polls the existing runtime status and readiness gates, invokes
only `precheck` and `start`, verifies `result=running`, and consumes its single
attempt for the boot. Host tests cover strict configuration, readiness waiting,
successful startup, the one-attempt limit, and missing-config dormancy.
Firmware `1d0ce1ad-c228-5764-2327-c7d7d2536017` passed both candidate and
ordinary-reboot acceptance. The worker waited without consuming its attempt,
started all three vendor processes after readiness, preserved Nerves watchdog
ownership and network health, and finalized new recordings after both starts.
Prior-boot transient runtime markers now normalize to `prepared`, while
same-boot degradation remains visible. Exact final firmware
`ba2a02ba-e525-5f86-cf35-40343d3f1ff5` repeated candidate validation,
one-attempt startup, process/isolation health, clean updater state, stable
networking, and recording finalization. The operator then confirmed that the
standard Atom mobile application connected and worked normally.

## Consequences

The design keeps the ordinary Nerves boot and operational model intact and
reuses only the irreplaceable vendor camera components.

It adds a second userspace ABI and privileged camera drivers, so physical
testing is mandatory and the compatibility service can never be treated like a
normal portable Nerves application.

The stock vendor startup path cannot be reused. A small amount of Atom Cam
2-specific module, process, watchdog, network-status, and storage-check
compatibility code is unavoidable.

NAS support does not require an in-kernel mount. Reusing OTP SFTP preserves the
protected-kernel verification contract and avoids adding a second network
daemon or a broad vendor compatibility layer. The tradeoff is that the target
NAS must provide a restricted SFTP account.

## References

- [`mnakada/atomcam_tools`](https://github.com/mnakada/atomcam_tools)
- [`atomcam_tools` runtime architecture](https://github.com/mnakada/atomcam_tools/blob/main/build.md)
- [`atomcam_tools` camera startup](https://github.com/mnakada/atomcam_tools/blob/main/overlay_rootfs/atom_patch/system_bin/atom_init.sh)
- [`atomcam_tools` completed-recording hook](https://github.com/mnakada/atomcam_tools/blob/main/overlay_rootfs/atom_patch/bin/mv)
