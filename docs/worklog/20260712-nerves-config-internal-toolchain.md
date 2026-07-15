# 20260712 nerves-config internal toolchain investigation

## Status

This records an early build-system mismatch. The temporary internal-toolchain workaround was superseded by the dedicated external non-DSP Nerves toolchain required for the Ingenic T31 runtime.

See [`20260713-atomcam2-toolchain-dsp-ase-investigation.md`](20260713-atomcam2-toolchain-dsp-ase-investigation.md).

## Symptom

The build reached `nerves-config` after building the toolchain, Linux, Erlang, `erlinit`, and `nerves_heart`, then failed while copying `echo-gcc-args`:

```text
cp: cannot create regular file '.../host/opt/ext-toolchain/bin/echo-gcc-args': No such file or directory
```

## Finding

The bring-up configuration was using Buildroot's internal toolchain, while `nerves-config` expected the directory structure used by an external Nerves toolchain:

```text
host/opt/ext-toolchain/bin
```

Deleting `.nerves` reproduced the failure, so stale build state was not the cause.

## Temporary workaround

The expected host directory was created before `nerves-config` installed its helper.

This allowed the build investigation to continue, but it was not the final toolchain design.

## Final resolution

Runtime testing later proved that the stock MIPSEL Nerves toolchain enabled DSP ASE instructions unsupported by the Atom Cam 2's Ingenic T31 processor.

The final platform therefore requires a consistent external toolchain with:

```text
MIPS32 Release 2
little-endian
O32 ABI
soft-float
musl
DSP ASE disabled
```
