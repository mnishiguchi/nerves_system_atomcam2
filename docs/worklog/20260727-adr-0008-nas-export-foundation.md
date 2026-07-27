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

The exporter processes at most ten new segments per run and naturally retries
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

## Remaining production acceptance

The transport behavior is physically proven. Phase 4 still needs the intended
NAS account and a sustained recording trial to validate:

- production backlog catch-up and oldest-first eviction of exported files;
- the production NAS's SFTP permissions and storage layout;
- approximately 20-day retention on that NAS; and
- stable mobile live view, playback, Wi-Fi, SSH, watchdog ownership, and
  firmware validation during sustained export.
