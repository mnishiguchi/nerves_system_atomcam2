# ADR 0008 Phase 4: NAS export foundation

Date: July 27, 2026

## Scope

Choose and implement the smallest NAS transport that preserves the protected
control kernel and the corrected vendor-camera/mobile behavior.

## Transport finding

The physical v0.2.0 device reports the fixed verified kernel:

```text
Linux 3.10.14__isvp_swan_1.0__
```

Neither `nfs` nor `cifs` is registered in `/proc/filesystems`, and no matching
client module exists in the application root filesystem. The repository kernel
defconfig is not evidence for the shipped control kernel because the packaging
flow deliberately replaces that build output with the verified vendor image.

The running Erlang release does include OTP SSH 6.0.1 and
`ssh_sftp.beam`. SFTP therefore provides a client path without changing the
kernel, importing vendor SMB code, adding a FUSE layer, or starting another
daemon.

## Implemented boundary

`Atomcam2NervesApp.NasExporter` is supervised on target but remains inert until
explicit `/data` configuration enables it.

The first transport:

- uses a dedicated key-based SFTP account;
- requires a pre-provisioned NAS host key;
- accepts only finalized `YYYYMMDD/HH/MM.mp4` spool paths;
- uploads to an `.uploading` name and renames after size verification;
- treats an equal-size final path as an idempotent retry;
- reports a different-size final path as a conflict;
- records completion outside the vendor-visible spool;
- retains exported MP4 files locally for recent mobile playback;
- evicts the oldest successfully exported local files only above a configured
  byte target, preserving unexported files even when an outage exceeds it; and
- deletes only recognized recordings under remote date directories older than
  the configured retention period.

The exporter processes at most two new segments per run and naturally retries
after connection or NAS failures on the next poll. Missing or invalid
configuration cannot affect camera startup, Wi-Fi, SSH, firmware health, or the
hardware watchdog.

## Host validation

The host suite covers:

- strict enabled and disabled configuration;
- rejection of passwords, unknown keys, duplicate keys, relative key
  directories, and unsafe remote roots;
- selection of only finalized regular MP4 paths;
- rejection of symlinks and unexpected names;
- oldest-first eviction of successfully exported local files without deletion
  of unexported files;
- successful-export markers without immediate local deletion; and
- compact recording-date retention boundaries.

## Physical transport acceptance

Firmware `acb7f0a2-1189-505d-8ea5-7c82b71c03a5` was uploaded to the physical
Atom Cam 2. It validated normally with the exporter supervised and
`last_result=:not_configured`. The camera runtime then restarted successfully,
kept Nerves watchdog ownership, remained reachable for 30 of 30 pings, and
finalized a new local MP4.

A disposable OTP SFTP endpoint on the workstation exercised the actual target
client:

```text
source=20260727/13/26.mp4
bytes=3556322
uploaded=1
temporary_files_after_completion=0
sha256=1a52d96a3de461fd6a1b15daea84bf3480cf54a3c4d8a83d67a651c51e1c04f1
```

The source and destination SHA-256 values matched. Repeating the same export
reported `already_present=1` and did not upload a duplicate.

For retention, a disposable `20260706/00` directory contained one MP4, one
`.mp4.uploading` file, and one unrelated text file. With July 27 as the device
date and a 20-day policy, the exporter removed the two recording-shaped files
and left the unrelated file.

An export to a closed port returned `connect_failed: econnrefused`, preserved
the local MP4, and did not affect the camera runtime or validated firmware.
The next attempt against the live endpoint succeeded as an idempotent retry.

The disposable SFTP daemon was stopped after the trial. Its test-only private
key and host-key data were permanently removed from both `/data` and the
workstation.

## Production preparation

The physical camera accumulated 531 finalized one-minute segments while the
vendor runtime and standard mobile application remained usable. Before the
production NAS was identified, a dedicated 3072-bit RSA client key was
provisioned under `/data/atomcam2-vendor-camera/nas-ssh`:

```text
fingerprint=SHA256:kcAlb/2KOdrwaZN+JGSIUIEQc9zXfDmJQDc9ShhRfzI
key_directory_mode=0700
private_key_mode=0600
```

The temporary workstation copy was securely removed. No
`nas-export.conf` was created, so the exporter remained disabled and did not
transfer or delete any local recording.

Reviewing the accumulated backlog exposed an unsafe pressure boundary in the
initial implementation: it could evict the oldest finalized file without
first proving that file had been published. Spool eviction now accepts only a
size-matching successful-export marker written after atomic remote
publication. A missing or stale marker preserves the local recording even
when the spool remains above its configured target.

Firmware `dfce7521-1ab0-5805-f856-e29774feb386` carried this correction to the
physical camera. The vendor runtime was stopped cleanly before installation.
All 536 finalized recordings totaling 1,286,578,243 bytes survived the update,
and a 537th recording finalized after automatic camera startup. The candidate
validated in slot B, the private key retained mode `0600`, the exporter
remained unconfigured, Nerves heart remained active, and networking passed 30
of 30 pings.

An isolated target fixture under `/tmp` confirmed the production behavior:

```text
exported_local_removed=true
unexported_local_preserved=true
stale_marker_preserved=true
remaining_bytes=20
```

The fixture was removed after the check. No production spool path participated
in the eviction test.

## Temporary LMDE SFTP acceptance

Before provisioning the intended NAS, the LMDE 7 workstation hosted a
temporary OTP SFTP endpoint on `192.168.10.111:10022`. The endpoint used the
camera's dedicated public key, a temporary ED25519 host key, and OTP's
application-level `root` option to expose only:

```text
/tmp/atomcam2-sftp-acceptance-20260727/root
```

No system SSH daemon, privileged port, password, or permanent workstation
account change was required. The camera configuration was first installed with
`enabled=false`, a 2 GiB spool target above the 1.46 GB backlog, and strict
host-key verification. A zero-file authenticated preflight passed before
export was enabled.

The first attempt used a 10-second poll interval to accelerate the backlog. It
published 52 files, while the nearly continuous SFTP work coincided with
console and MOTD calls missing their short timeouts and the camera later
becoming unreachable on the LAN. The temporary endpoint was stopped, leaving:

```text
remote_finalized=52
remote_partial=20260727/08/45.mp4.uploading
remote_partial_bytes=1310720
local_source_bytes=1918448
local_completion_marker=false
```

The operator power-cycled the camera. The endpoint remained stopped while the
configuration was changed back to `enabled=false`. All 570 local recordings
were present, the 52 final remote files had matching completion markers, and
the interrupted local source remained intact. Volatile previous-boot evidence
was unavailable after the physical power cycle, so this trial does not assign
a definitive cause to the loss of reachability.

The retry used the normal 60-second interval. It removed the partial temporary
file, re-uploaded the intact local source, verified its size, published the
final name, and only then wrote the marker. Source and destination matched:

```text
path=20260727/08/45.mp4
sha256=dba1487a52149ddff9cf6cca02731022ce2fbf49f2a33c057bdcc9e4eca91415
bytes=1918448
```

An earlier sample also matched at both ends:

```text
path=20260727/07/51.mp4
sha256=9bc48d0b4205ccf938f74bd0f8966d09d84de71fa8236becfdafd15d2e7f4bb7
bytes=612004
```

Removing only that sample's local marker and rerunning the exporter reported
`already_present=1`, uploaded nine new files, and recreated the marker without
duplicating the existing final path.

The 20-day retention pass removed both an expired `.mp4` and an expired
`.mp4.uploading` fixture below `20260706/00`, while preserving `keep.txt`.
Sustained normal-cadence export then reached:

```text
remote_finalized=131
remote_mp4_bytes=253609144
remote_uploading=0
local_spool_files=586
local_spool_bytes=1537734443
local_completion_markers=131
local_spool_deleted=0
```

During the throttled recovery, the camera answered 45 of 45 pings and a later
30 of 30 pings. After export was disabled and the endpoint stopped, it answered
another 30 of 30 pings. The vendor runtime remained running, firmware remained
validated in slot B, Nerves heart remained active, and both firmware updater
directories remained empty.

The temporary archive remains on the workstation for operator inspection.
The camera profile is left at `enabled=false`.

The exporter now rejects poll intervals below 60 seconds. Polling faster than
the one-minute recording cadence has no steady-state value and can
unnecessarily saturate this single-core target during backlog catch-up.

Final firmware `069c6642-db31-5c6f-be14-c2756e6ee2c9` was installed into slot
A after stopping the vendor runtime cleanly. It validated, synchronized time,
and started the opt-in vendor runtime once. `heart` retained the physical
watchdog, the exporter remained disabled, all 590 pre-update recordings and
131 completion markers survived, and a 591st recording finalized after boot.
The private key, `known_hosts`, and exporter configuration also persisted with
mode `0600`. The deployed parser rejected a 59-second interval, the firmware
upload directory was empty, and the running camera answered 30 of 30 pings.
After a subsequent physical power cycle, the operator confirmed SSH through
`nerves.local` and normal operation in the standard Atom mobile application.

## Production LMDE endpoint preflight

The intended endpoint is the LMDE 7 workstation at `192.168.10.111:22`, using
the dedicated `atomcam` OpenSSH `internal-sftp` account and the account's
session start as the recording root. The workstation had 394 GB available.
Its ED25519 host-key fingerprint was verified locally as:

```text
SHA256:GE1Kt0MHSzYd++6R4Y4vNZzZuyZ2ZCKSaxVtss/t4jU
```

The verified host key and disabled production profile were installed
atomically on the camera. With strict host-key checking and the device-private
key, the camera authenticated, listed `.`, wrote and statted a 22-byte probe,
deleted it, and closed the SFTP connection. The exporter remained disabled.

The first server profile forced `internal-sftp` into the recording directory
but did not chroot the account. Production enablement was therefore blocked
until the account was confined. A small ignored workstation script staged a
root-owned `/srv/atomcam-recordings` chroot, exposed only its writable `data`
directory as the session start, disabled forwarding and TTY access, checked
the camera-key fingerprint, validated `sshd`, and reloaded OpenSSH.

Firmware `09dbb2e2-edf4-5a76-d202-273f245479c2` adds support for exactly `.`
as a configured remote directory while continuing to reject `/`, parent
traversal, and embedded current-directory components. It validated in slot B,
left export disabled with a 2 GiB spool target, started the vendor runtime
once, and answered 30 of 30 pings.

The operator then applied the workstation script. The resulting account is
chrooted to the root-owned `/srv/atomcam-recordings`, starts in its writable
`data` directory, accepts only the camera key, and has no forwarding, TTY, or
shell access. From the camera, listing `/etc` failed outside the chroot while a
write, stat, and delete probe in `.` succeeded.

Completion markers from the disposable port-10022 endpoint were archived
before production enablement. Markers represent publication to one specific
endpoint and must not be reused after changing the destination. The fresh
production marker directory started empty; no local recording was removed.

Two production runs from the ten-file firmware published 20 recordings
atomically. The first sampled destination matched its local SHA-256 and neither
run left an `.uploading` file. The 2 GiB spool threshold remained above the
approximately 1.75 GB backlog, so all 20 marked source recordings remained
available locally.

After the second run, and after an interactive diagnostic accidentally printed
an entire MP4 into the Nerves console, the camera stopped responding on the
LAN. The two events are confounded and no definitive cause is assigned.
OpenSSH was stopped on the workstation before the operator power-cycled the
camera. Recovery preserved 658 finalized recordings, all 20 production
markers, and all 20 corresponding local sources. The exporter was immediately
disabled again.

As conservative hardening for the single-core camera, the per-run batch is now
two files at the normal one-minute interval. This sustains the one-file-per-
minute recording rate while draining one additional backlog file per minute,
without continuous SFTP work.

Firmware `174c476f-9489-50c2-548c-4b62df277f9f` (`barrel-gain`) installed and
validated in slot A with the workstation SFTP service still stopped. The
exporter remained disabled, the vendor camera runtime started once, `heart`
retained `/dev/watchdog0`, 665 local recordings and all 20 production markers
were present, both updater directories were empty, and networking passed 30 of
30 pings.

## Clean production reproduction and bounded transport

With the normal 60-second cadence and two-file batch, the first production
continuation raised the fresh marker count from 20 to 48 across 14 runs. Each
successful run retained its local sources. The device later became unreachable
and required a physical power cycle. Recovery with the workstation SSH service
stopped found 687 local recordings, all 48 production markers, all 131 archived
disposable markers, and no missing size-matching marked source. The exporter
was immediately disabled.

The backlog path was simplified before repeating the trial. Pending-file
selection now stops after finding two unmarked files, one immutable spool
snapshot is reused for the run, and spool enforcement performs no marker reads
while the snapshot is below the configured limit. On target firmware
`de5c7e2b-9ab7-53cb-ab74-7e2d26ba1566` (`table-focus`), a 693-file snapshot
took 4,136 milliseconds while below-limit enforcement on that snapshot took
zero milliseconds. Erlang memory remained about 26 MiB.

A second production run removed the earlier interactive-console confounder.
The only workstation-side observation was continuous ping plus OpenSSH service
logging. OpenSSH accepted exactly 12 clean SFTP sessions; each completed and no
server error or leaked server process appeared. The production marker count
therefore rose from 48 to 72. No thirteenth connection reached the server.
Ping was initially stable, then became intermittent, briefly recovered, and
eventually stopped. The device hardware watchdog did not restore reachability,
so the workstation SSH service was stopped before another physical power
cycle.

A temporary device-local diagnostic, persisted under `/data`, distinguished
the failure from unbounded memory growth:

```text
baseline_erlang_total_mb=approximately 26
trial_erlang_total_mb=approximately 26_to_28
baseline_exporter_function=gen_server:loop/5
stalled_exporter_function=gen:do_call/4
```

During healthy cycles the exporter returned to its GenServer loop. It later
remained in `gen:do_call/4`, diagnostic intervals slipped, and process and port
counts fell while total Erlang memory stayed bounded. Review of the OTP SSH
implementation found that SFTP client-channel calls wait with an outer
`infinity` and rely on a timer inside the channel process. The exact SFTP
subcall was not isolated, but the failure boundary is an unreturned synchronous
OTP transport call rather than the completed-file scan or a growing Erlang
heap.

The first mitigation invoked the whole transport in an unlinked monitored
process with a 30-second outer deadline. A target-only probe proved that it
terminated a blocked call, but follow-up review and server-side session history
showed an important flaw: killing the transport owner can skip the `after`
blocks responsible for closing the SFTP channel and SSH connection.

Firmware `eafb221d-e366-5cd1-4f2c-42ee129d9c10` (`trigger-yard`) replaces that
whole-transfer kill with a hard deadline around each OTP SSH/SFTP operation.
The transport owner retains the exact channel and connection handles and
always unwinds through cleanup. Cleanup itself is bounded; as a final fallback
it terminates the exact resource process. A connection-refused trial returned
promptly, left `:sshc_sup` empty, preserved all unexported recordings, and
passed 30 of 30 pings.

Two subsequent production cycles against the confined LMDE 7 endpoint
published four finalized recordings atomically. The spool policy removed only
local recordings whose remote publication had completed, and it removed their
completion markers with them. The remaining approximately 2.20 GB consisted
of unexported recordings and was preserved above the configured 2 GiB target.
Camera reachability stayed stable throughout. After export was disabled,
`:sshc_sup` was empty and the server retained only its listener, with no
per-session `sshd` processes.

Final firmware `efc08024-9abe-5a5d-6d68-be70ce82b5bc` (`uncover-skill`)
removes the whole-transfer deadline entirely. Its first upload attempt with the
vendor runtime active lost reachability before committing a candidate; the
existing validated slot B recovered on power cycle. After the runtime was
stopped cleanly, the same bundle installed in slot A, rebooted, validated, and
automatically restarted the opt-in runtime. This establishes a simple
operational rule: stop the optional compatibility runtime before OTA to leave
the constrained device maximum memory and flash-I/O headroom.

The exact final image then completed one deliberately limited production
cycle. It atomically published two recordings and removed only those two local
files after publication. The remaining 2,818,758,555 bytes were unexported and
therefore remained local despite exceeding the configured 2 GiB target.
Networking passed 87 of 87 pings, the vendor runtime and Nerves watchdog stayed
healthy, and cleanup again left `:sshc_sup` empty and only the NAS listener
process. Persistent export configuration was returned to `enabled=false`.
All 42 host tests pass.

## Remaining production acceptance

The transport and intended confined account are physically proven. Phase 4
still needs a sustained trial with the per-operation deadlines to validate:

- production backlog catch-up and oldest-first eviction of exported files;
- approximately 20-day retention on that NAS; and
- stable mobile live view, playback, Wi-Fi, SSH, watchdog ownership, and
  firmware validation during sustained export.
