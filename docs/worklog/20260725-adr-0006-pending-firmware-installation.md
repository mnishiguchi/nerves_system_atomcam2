# ADR 0006 pending firmware installation validation

## Summary

Implemented and validated the first pending firmware installation workflow for
ADR 0006 on physical AtomCam 2 hardware.

## Validation steps

- Built the immutable boot manager SquashFS image.
- Verified the embedded boot manager init script matched the source.
- Installed the diagnostic boot manager image on the FAT boot partition.
- Reproduced a metadata write failure caused by the minimal boot environment
  not providing `sync`.
- Updated metadata writes to tolerate environments where `sync` is unavailable.
- Rebuilt the boot manager image and verified the updated helper was embedded.
- Booted AtomCam 2 successfully into the Nerves application.

## Observed boot state

The boot manager reported successful handoff to the application root: 

```text
stage=application_root
boot_metadata_confirmed_slot=A
boot_policy_selected_slot=A
boot_policy_selection_reason=pending_attempt_limit
```

## Notes

Application-level automatic confirmation after health checks remains a future
integration step. The boot metadata protocol already provides the required
operations for that integration.
