# Nerves artifact baseline

## Scope

This worklog records the artifact distribution state before implementing
ADR 0003.

- Date: 2026-07-18
- Branch: `feat/distribute-nerves-artifacts`
- Commit: `1c0ba6f985f862d4a63903369679bba2dc90ded6`
- System version: `0.1.0`
- Toolchain version: `0.1.0`
- Host: Linux x86_64

## Published state

The repository has no `v0.1.0` Git tag or GitHub release.

The only existing tag observed during the baseline was:

```text
verified-atomcam2-ping-ssh-baseline
```

## Expected artifacts

The root Nerves project attempted to download:

```text
nerves_system_atomcam2-portable-0.1.0-0AD109E.tar.gz
nerves_toolchain_atomcam2-linux_x86_64-0.1.0-FB9E9DE.tar.xz
```

Both packages resolve from:

```text
Repository: mnishiguchi/nerves_system_atomcam2
Release tag: v0.1.0
Download method: github_release
```

Both downloads returned HTTP 404 because the release and assets do not exist.

The previously observed system artifact ended in `BE444FF`. The current source
expects `0AD109E`, confirming that the system checksum inputs changed.

## Example application result

A clean-cache `mix deps.get` in the example application failed before Nerves
artifact resolution:

```text
fatal: couldn't find remote ref v0.1.0
```

The example application references the system repository at the nonexistent
`v0.1.0` tag.

## Toolchain project result

Running the toolchain project independently resolved Nerves `1.15.0`, while
the root project currently uses Nerves `1.14.3`.

The standalone command then failed with:

```text
Compiling Nerves packages requires nerves_bootstrap to be started
```

The exact toolchain filename was nevertheless reported by the root Nerves
environment.

## Reproducibility findings

The system package currently uses the same list for package contents and
artifact checksum inputs.

The checksum includes files that do not directly affect the generated system,
including:

- `docs`
- `scripts`
- `toolchain`
- `README.md`
- `CHANGELOG.md`

Documentation and release-process changes therefore alter the expected system
artifact filename.

The existing release script does not build the toolchain through
`mix nerves.artifact`. It calculates the checksum separately and archives the
directory supplied through `NERVES_TOOLCHAIN`.

## Next milestone

Separate the root package contents from the files that materially affect the
system artifact checksum.

Do not create the `v0.1.0` tag or GitHub release until both artifact
configurations and archives have been verified manually.
