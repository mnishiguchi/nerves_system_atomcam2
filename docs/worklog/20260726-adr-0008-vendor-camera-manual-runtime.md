# 20260726 ADR 0008 vendor camera manual runtime

> Historical note: the later mobile test disproved the assumption that
> `assis` could be omitted. The corrected process and storage behavior is
> recorded in
> [`20260726-adr-0008-mobile-and-storage-compatibility.md`](20260726-adr-0008-mobile-and-storage-compatibility.md).

## Result

The console-visible portion of the ADR 0008 Phase 2 manual runtime is complete
on physical Atom Cam 2 hardware.

The implementation can prepare private vendor state, load the minimal camera
driver set, run `hl_client` and `iCamera_app` without `assis`, report health,
and cleanly stop its processes, mounts, and System V IPC. Nerves retained
control of Wi-Fi, SSH, firmware validation, and the hardware watchdog throughout
the trial.

Standard Atom mobile-application live viewing was not observable from the
device console and remains an operator acceptance check. No recording hook,
automatic boot integration, or NAS exporter is implemented.

## Commands

The target exposes one deliberately small command surface:

```sh
atomcam2-vendor-camera precheck
atomcam2-vendor-camera prepare
atomcam2-vendor-camera start
atomcam2-vendor-camera status
atomcam2-vendor-camera stop
```

The runtime does not start during boot. `prepare` is idempotent. After `stop`,
the protected kernel requires a reboot before the next `start` because its
camera modules are permanent.

## Private state

`prepare` copies the protected `/atom/configs` tree to:

```text
/data/atomcam2-vendor-camera/configs
```

The command:

- requires `/atom/configs` to remain the expected read-only JFFS2 mount;
- uses a temporary sibling directory and an atomic rename;
- applies owner-only permissions;
- records a schema marker only after the copy succeeds; and
- never prints protected configuration contents.

Logs, runtime state, and the future local spool live below the same mode-private
root:

```text
/data/atomcam2-vendor-camera/logs
/data/atomcam2-vendor-camera/state
/data/atomcam2-vendor-camera/spool
```

The private configuration survived the tested A/B firmware upload, as expected
for `/data`.

## Compatibility boundary

The command does not run the stock `app_init.sh`. It loads only:

```text
tx_isp_t31
audio
avpu
sinfo
sensor_gc2053_t31
sample_pwm_core
sample_pwm_hal
speaker_ctl
```

The GC2053 module is loaded with `data_interface=1`. An initial probe used the
module object's static default, but the running vendor SDK log showed its
authoritative request:

```text
insmod /system/driver/sensor_gc2053_t31.ko data_interface=1
```

The corrected trial therefore uses interface 1 from the start.

The vendor processes run in the protected uClibc root through `chroot`. Private
tmpfs mounts cover transient `/tmp`, `/run`, `/dev`, `/media`, and `/sbin`
paths. The compatibility view receives only selected camera devices, the
private configuration copy, the local spool, and read-only procfs and sysfs.
The real `/dev/watchdog*` nodes are absent.

Only these vendor processes are started:

```text
hl_client
iCamera_app
```

The watchdog-owning `assis` and the stock Wi-Fi, factory, USB, update, and
storage helpers are omitted.

The process capability bounding mask observed during the trial was:

```text
CapBnd: 0000001ff79eefff
```

The runtime explicitly drops `CAP_SYS_ADMIN`, `CAP_SYS_BOOT`,
`CAP_NET_ADMIN`, `CAP_SYS_MODULE`, and `CAP_MKNOD`, and sets `no_new_privs`.
Commands for networking, flash, mounting, module management, power control, and
broad process termination are hidden or replaced in the private command path.
The vendor processes remain root and retain the narrow hardware access needed
by the camera; the chroot is a compatibility boundary, not a security sandbox.

## Physical trial

The corrected test firmware was:

```text
Firmware UUID: 4beff2b6-daa1-58fb-12fd-7ca0a2dff7ac
Nerves MOTD name: era-uncover
candidate slot: B
```

It was installed through the standard target fwup SSH subsystem. After boot,
the system automatically validated Slot B.

The corrected pre-start check found:

```text
failures=0
gates=2
warnings=1
```

The remaining gates were the deliberately omitted `assis` behavior and
mobile-application viewing. The NFS warning is expected because the protected
v0.2.0 kernel does not expose an NFS client.

No camera module or vendor camera process was present before `start`. `start`
then reported:

```text
PASS Nerves heart owns the hardware watchdog before start
PASS private device view excludes the hardware watchdog
PASS Nerves heart still owns the hardware watchdog
PASS manual vendor camera processes are running without assis
PASS manual vendor camera runtime started
```

After the stability interval, `status` reported:

```text
state=running
process=iCamera_app rss_kb=3228 state=running
process=hl_client rss_kb=428 state=running
watchdog_isolation=assis_omitted
private_watchdog_view=absent
memory_reclaimable_kb=46560
result=running
```

The process RSS was about 3.7 MiB combined. Reclaimable memory decreased from
about 50 MiB before start to about 45.5 MiB while running and remained stable
during the bounded trial. SSH stayed connected, `wlan0` retained its address,
and Nerves `heart` remained the sole `/dev/watchdog0` owner.

## Stop and recovery

Every selected vendor camera module reports `[permanent]` in `/proc/modules`.
Attempting to unload them is therefore neither useful nor part of the stop
contract.

`stop` returned success after:

- terminating only the two recorded process IDs;
- removing only System V IPC created after the pre-start snapshot;
- unmounting only the recorded compatibility mounts in reverse order; and
- revealing the original read-only `/atom/system` and `/atom/configs` mounts.

It then reported:

```text
state=stopped-reboot-required
result=stopped_reboot_required
```

No vendor camera process or private compatibility mount remained. All selected
camera modules remained loaded, as required by the protected kernel.

A deliberate `Nerves.Runtime.reboot/0` returned the device to the same validated
Slot B with Wi-Fi and SSH healthy. No vendor camera process or selected camera
module was present after reboot. `status` treats a reboot-required marker from
an earlier boot as `prepared`, while the next `start` also clears stale
transient state.

The final status correction was packaged as firmware
`f08a534a-20b2-59f3-7d22-03db801101ee` (`two-lonely`) and validated in Slot A.
With the earlier reboot marker still present under `/data`, it reported:

```text
state=prepared
process=iCamera_app state=stopped
process=hl_client state=stopped
watchdog_isolation=assis_omitted
result=stopped
```

No selected camera module or vendor process was present.

## Remaining Phase 2 acceptance

While the manual runtime is running, an operator must confirm live viewing from
the already-paired standard Atom mobile application. The ADR intentionally does
not infer this from process liveness or vendor logs.

If live viewing succeeds, the next implementation boundary is Phase 3:
observing how the vendor finalizes a local recording segment and adding only the
minimum completion/path hook. If it fails, investigate the smallest missing
mobile-protocol dependency before starting recording work; do not import the
stock startup stack.
