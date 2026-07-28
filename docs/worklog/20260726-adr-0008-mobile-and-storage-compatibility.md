# 20260726 ADR 0008 mobile and storage compatibility

## Result

The device-side vendor camera runtime now reaches a healthy steady state on
physical Atom Cam 2 hardware:

- `assis`, `hl_client`, and `iCamera_app` remain running;
- vendor network and cloud initialization complete;
- Nerves retains Wi-Fi, DNS, SSH, and hardware-watchdog ownership;
- the vendor SD health and mount checks succeed against a `/data`-backed
  compatibility view;
- the real MicroSD block device is not visible inside the vendor runtime; and
- `stop` terminates vendor descendants and removes private mounts and IPC.

On July 27, 2026, the operator confirmed the standard mobile application,
live view, recorded playback, and healthy storage screen. Phase 2 is complete.

## Why the first manual runtime was incomplete

The earlier bounded console trial established the module, chroot, and
capability boundary, but it omitted `assis`. A later mobile test showed the
camera offline, and the application reported:

```text
SDカードに異常が発生しました。再挿入または交換してください。
```

Further physical testing established that `assis` is required for the vendor
mobile/cloud path. Starting the stock process unchanged was not acceptable:
it attempted to own the hardware watchdog and the vendor camera stack attempted
to restart Wi-Fi and prepare the raw SD device.

## Narrow compatibility behavior

The runtime now starts the stock process order:

```text
assis
hl_client
iCamera_app
```

A small freestanding preload library returns success for the four vendor
assistant watchdog calls. `/dev/watchdog*` remains absent from the chroot and
Nerves `heart` remains the sole owner of `/dev/watchdog0`.

The same library handles only the exact vendor storage mount pair:

```text
/dev/mmcblk0p1 -> /media/mmc
```

The source path is a bounded regular-file placeholder on the private device
tmpfs. The process has no `CAP_MKNOD`, and the placeholder is verified not to
be a block device. `/media/mmc` is already bind-mounted to the private spool
under `/data`. The shim therefore confirms an existing Nerves-owned mapping; it
does not mount or expose a block device.

Vendor commands that would manage Nerves-owned networking are successful
no-ops. The compatibility helper reports the current Nerves IPv4 address and
connected WPA state, restores the Nerves DNS file, and does not receive
`CAP_NET_ADMIN`.

The vendor `tf_prepare` and `blkid` probes are also emulated. They report a
healthy FAT camera card without giving the vendor access to the actual ext2
MicroSD partition. Direct mount operations remain unavailable because the
vendor processes do not receive `CAP_SYS_ADMIN`.

## Crash diagnosis

Before WPA status emulation, the vendor `net-serv` thread crashed with status
139. The kernel reported an invalid read at address `0x48`.

Disassembly showed that the vendor binary calls `fclose(NULL)` when
`/tmp/wpa.log` is absent and the WPA status does not contain `COMPLETED`.
Providing a private empty log and a read-only view of the Nerves connection
state avoids that vendor error path without starting a second supplicant.

## Physical validation

The final tested firmware was:

```text
Firmware UUID: ec4508c6-a345-5eae-1aa5-87d735363bcd
Nerves MOTD name: visa-despair
candidate slot: A
```

After mobile acceptance, the final runtime and system sources were rebuilt and
installed as:

```text
Firmware UUID: a78bfbe5-83af-59fb-b692-a41f2b6ca203
Nerves MOTD name: purse-lottery
validated slot: A
```

It reported both `storage_isolation=shim_active` and
`watchdog_isolation=shim_active`. All network, cloud, health, and mount markers
remained successful. Precheck reported zero failures, zero gates, the expected
Phase 4 NFS warning, and `result=ready_for_manual_camera_start`. After its final
OTA reboot, one MP4 finalized within the three-minute observation window while
one active MP4 remained under private `/tmp`.

After startup, status reported all three primary vendor processes running,
the assistant shim active, Nerves `heart` as the sole watchdog owner, and the
private watchdog view absent.

The fixed log counters reported:

```text
init_all() END ret:0=1
net_service init fail=0
Current network connect ok=1
hlcloud initialized success=1
(health_test) success=1
(health_test) fail=0
mmc mount ok=1
mmc mount fail=0
No mmc blk Dev=0
SD card failed=0
sdevice_open_do fail=0
```

Thirty consecutive pings succeeded while the final runtime initialized. SSH
remained available. The primary processes used about 23 MiB RSS combined and
the system retained about 32 MiB reclaimable memory during the observed
interval.

The vendor application also started one `rtsp`, one `live555MediaServer`, one
monitor shell, and one sleep process as internal descendants. ADR 0008 does not
expose or support RTSP as a product feature. Stop identifies processes by their
private `/atom` root, terminates those descendants, then removes only the
recorded compatibility mounts and new System V IPC.

## Mobile acceptance

The July 27 screenshots recorded:

- `Screenshot_20260727-082040.png`: AtomCam2 is online;
- `Screenshot_20260727-082058.png`: HD live view is active;
- `Screenshot_20260727-082120.png`: recorded playback and its timeline work;
  and
- `Screenshot_20260727-082405.png`: the storage screen reports
  `13.44 GB/13.59 GB`, local recording enabled, and continuous-recording mode.

The earlier SD-card error is absent.

## Local continuous-recording acceptance

The same running device provided 36 completed MP4 files under the private
`/data` spool:

```text
completed_mp4=36
completed_mp4_bytes=71611339
oldest_mp4=record/20260727/07/51.mp4
newest_mp4=record/20260727/08/26.mp4
completion_span_seconds=2100
unexpected_or_partial_files=0
```

Thirty-five intervals over 2,100 seconds establish a one-minute completion
cadence. The current `08/27` segment existed only as `/tmp/27.mp4`, while
`08/26.mp4` was the newest completed spool file. Incomplete and completed files
therefore already have a clear boundary: the vendor runtime writes the current
segment in private tmpfs and moves it into the `/data`-backed media path after
finalization.

No additional recording-path or completion hook is needed for Phase 3.
NAS export, retry, spool limits, and retention remain Phase 4.
