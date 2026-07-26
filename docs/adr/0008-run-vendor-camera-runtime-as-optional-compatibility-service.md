# ADR 0008: Run the vendor camera runtime as an optional compatibility service

## Status

Accepted on July 26, 2026

The read-only feasibility gate and console-visible Phase 2 checks are complete.
Standard mobile-application live viewing remains an open operator acceptance
check; recording and NAS export remain later phases.

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

A subsequent physical manual-runtime trial also established that:

- `hl_client` and `iCamera_app` remain running without `assis`;
- Nerves `heart` retains sole hardware-watchdog ownership;
- the vendor-requested GC2053 sensor interface is `data_interface=1`;
- the two vendor processes use about 3.7 MiB combined RSS in the bounded trial;
- Nerves Wi-Fi, SSH, firmware validation, and recovery remain healthy; and
- the protected kernel marks every selected camera module permanent, so stop
  can clean processes, mounts, and IPC but a reboot is required to remove the
  modules.

That evidence is recorded in
[`../worklog/20260726-adr-0008-vendor-camera-manual-runtime.md`](../worklog/20260726-adr-0008-vendor-camera-manual-runtime.md).

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
process list instead. Do not load the vendor Wi-Fi, exFAT, USB Ethernet, MMC
detection, factory-test, or firmware-update components.

The compatibility service must not disable Nerves `heart` or release its
hardware-watchdog ownership. If `iCamera_app` cannot remain healthy without a
watchdog-owning `assis`, stop the implementation and revise this ADR. A small,
explicit compatibility shim may be considered only after a manual test proves
it is necessary; importing the broad `atomcam_tools` preload layer is not the
default.

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

### Recording boundary

The vendor runtime may create and finalize one-minute MP4 segments in a local
spool below `/data`. Incomplete files and completed files awaiting export must
have separate paths or an equally explicit state transition.

Use the smallest confirmed completion hook. `atomcam_tools` intercepts the
vendor move of a finished recording from `/tmp` into `/media/mmc/record`; that
behavior is useful evidence, but its combined CIFS, webhook, scheduling, and
path-rewrite scripts are not adopted.

The vendor runtime must not mount or write to the NAS directly.

### NAS export and retention

A separate Nerves-supervised exporter owns NAS delivery. It must:

- consume only completed local segments;
- retry after network and NAS outages;
- copy to a temporary destination name and rename atomically after completion;
- make repeated attempts idempotent;
- place a configured upper bound on the local spool; and
- remove NAS recordings older than the configured retention period.

Evaluate NFS first, but do not assume it is available. The protected v0.2.0
kernel does not currently register NFS or CIFS. Phase 4 must either prove a
small supported client path or make a separate kernel decision before adding an
exporter. It must not silently fall back to vendor SMB code.

### Boot, failure, and recovery behavior

Manual start remains the only supported mode until the physical validation
matrix passes.

After that validation, automatic startup may be enabled only by explicit
persistent configuration under `/data`. Startup must wait for:

- `/data` mounted read-write;
- Nerves networking healthy;
- synchronized or otherwise trustworthy system time; and
- a successful compatibility precheck.

The supervisor must use bounded restart attempts and visible failure state. It
must not create a reboot loop or restart Nerves networking. Stop must terminate
only the vendor processes and remove only compatibility mounts and IPC. The
selected modules are permanent in the protected kernel and must remain loaded
until a deliberate reboot. The command must report this state rather than
attempting unsafe or ineffective unload operations.

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
explicit module list and launches only `hl_client` and `iCamera_app`. The
compatibility environment omits the real watchdog, hides or replaces commands
that can alter networking, flash, mounts, modules, or power state, and removes
the corresponding capability classes from the vendor processes.

The physical trial resolved the watchdog conflict, minimal process list, memory
measurement, private configuration behavior, clean stop, and reboot recovery.
The runtime remains disabled by default and has no boot integration.

Standard mobile-app live viewing is still unconfirmed. That check is the final
Phase 2 acceptance item and must pass before recording hooks are treated as the
next implementation boundary.

## Consequences

The design keeps the ordinary Nerves boot and operational model intact and
reuses only the irreplaceable vendor camera components.

It adds a second userspace ABI and privileged camera drivers, so physical
testing is mandatory and the compatibility service can never be treated like a
normal portable Nerves application.

The stock vendor startup path cannot be reused. A small amount of Atom Cam
2-specific mount, module, process, and possibly watchdog compatibility code is
unavoidable.

NAS support cannot begin with an in-kernel NFS mount on the current protected
kernel. That limitation is deferred to Phase 4 rather than broadening the
camera-runtime milestone.

## References

- [`mnakada/atomcam_tools`](https://github.com/mnakada/atomcam_tools)
- [`atomcam_tools` runtime architecture](https://github.com/mnakada/atomcam_tools/blob/main/build.md)
- [`atomcam_tools` camera startup](https://github.com/mnakada/atomcam_tools/blob/main/overlay_rootfs/atom_patch/system_bin/atom_init.sh)
- [`atomcam_tools` completed-recording hook](https://github.com/mnakada/atomcam_tools/blob/main/overlay_rootfs/atom_patch/bin/mv)
