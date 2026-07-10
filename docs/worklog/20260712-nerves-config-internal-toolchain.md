# 20260712 nerves-config internal toolchain fix

## Goal

Continue the first `mix firmware` build for the AtomCam2 Nerves system.

## What happened

The build reached `nerves-config` after successfully building the toolchain, Linux,
Erlang, `erlinit`, and `nerves_heart`.

`nerves-config` failed while copying `echo-gcc-args`:

```text
cp: cannot create regular file '.../host/opt/ext-toolchain/bin/echo-gcc-args': No such file or directory
```

## Finding

The current system uses Buildroot's internal toolchain during bring-up. However,
`nerves-config` expects the external Nerves toolchain directory layout:

```text
host/opt/ext-toolchain/bin
```

Deleting `.nerves` did not change the result, so this is a deterministic system
configuration issue rather than stale build state.

## Decision

Create the expected host directory before `nerves-config` installs.

This is a small compatibility shim for the current first-boot build. It does not
change the target runtime design.

## Follow-up

Longer term, decide whether AtomCam2 should keep using Buildroot's internal
toolchain or move to a dedicated external Nerves-style MIPS toolchain.
