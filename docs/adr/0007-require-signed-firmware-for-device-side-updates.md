# ADR 0007: Require signed firmware for device-side updates

## Status

Proposed

## Context

ADR 0006 introduces device-side firmware installation through fwup and the SSH
firmware subsystem.

SSH authentication protects access to the update endpoint, but firmware
authentication is a separate concern. A firmware bundle may pass through build
workers, release storage, local disks, and transport layers before the device
applies it.

The device must reject firmware that was not produced by an authorized signer,
even when the update reaches the device through an authenticated administrator.

This project does not plan to adopt NervesHub at this stage. Firmware signing
must therefore work independently of NervesHub services.

## Decision

Require Ed25519-signed fwup firmware for every device-side `upgrade`.

Generate and manage at least two signing identities:

- A development signing key
- A release signing key

Private keys must never be committed to the repository or embedded in firmware.

The development private key may be stored in a developer-controlled local secret
store. The release private key must be stored offline or in an appropriately
protected continuous-delivery secret system with restricted access and audit
logs.

Embed one or more trusted public keys in the read-only system image.

Configure fwup and the SSH update subsystem so that:

- Device-side upgrades require a valid signature from a trusted key.
- Unsigned bundles are rejected before any inactive-slot write begins.
- A bundle signed by an unknown or retired key is rejected.
- Signature verification failure does not modify firmware-slot activation
  state.
- The same verification policy applies to local on-device fwup commands and
  `mix upload`.

Development builds must use the development key rather than bypassing signature
verification. This keeps the tested development path equivalent to the release
path.

Host-side `complete` installation with physical media access may remain
available for recovery, but release firmware produced for deployment must still
be signed.

Support key rotation by embedding multiple public keys temporarily:

1. Release firmware that trusts both the old and new keys.
2. Confirm deployment of that trust set.
3. Begin signing with the new key.
4. Confirm devices accept the new key.
5. Remove the old public key in a later firmware release.

Do not couple key management to NervesHub. Key creation, storage, signing,
verification, and rotation must remain usable with GitHub Releases, local
artifacts, `mix burn`, and `mix upload`.

## Consequences

### Positive

- Devices authenticate firmware independently of transport security.
- Compromise of a release download location does not permit unsigned firmware
  installation.
- The signing model works with local and SSH-based updates.
- Key rotation can occur without replacing every device physically.
- Future update services can reuse the same fwup trust model.

### Negative

- Release automation must have controlled access to a signing key.
- Losing all authorized private keys complicates future updates.
- Public-key removal requires a staged rotation.
- Developers must manage a development key.
- Recovery procedures must distinguish signature problems from media and
  firmware problems.

## Key-management requirements

- Keep private keys outside Git history.
- Do not print private keys or secret paths in workflow logs.
- Back up the release private key securely.
- Document who can sign a release.
- Record public-key fingerprints in release documentation.
- Separate development and release trust where practical.
- Make key rotation an exercised procedure rather than an untested emergency
  plan.
- Define a physical-recovery path for devices that trust no available signing
  key.

## Verification strategy

Test:

- A correctly signed development firmware
- A correctly signed release firmware
- An unsigned firmware
- A firmware modified after signing
- A firmware signed by an unknown key
- A firmware signed by a retired key
- Rotation firmware trusting old and new keys
- New-key firmware after rotation
- Signature failure before inactive-slot modification
- `mix upload` with valid and invalid signatures
- Local on-device fwup with valid and invalid signatures

Confirm that every rejected firmware leaves:

- The active slot unchanged
- The inactive slot either unchanged or explicitly disposable
- The pending-slot state unchanged
- The current firmware bootable

## Acceptance criteria

- All device-side upgrade paths require a recognized signature.
- Development and release firmware use separate private keys.
- No private signing key is stored in the repository or firmware.
- Trusted public keys are embedded in the read-only system.
- Invalid signatures are rejected before firmware activation state changes.
- Key rotation is documented and hardware-verified.
- `mix upload` rejects unsigned or untrusted firmware.
- Signing and verification work without NervesHub.

## References

- [`ssh_subsystem_fwup` update options](https://hexdocs.pm/ssh_subsystem_fwup/readme.html)
- [Fwup Elixir API](https://hexdocs.pm/fwup/Fwup.html)
