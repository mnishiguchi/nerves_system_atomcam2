# Atom Cam 2 Nerves toolchain package

This package describes the prebuilt MIPS32R2 soft-float toolchain used by
`nerves_system_atomcam2`.

The Ingenic T31 requires a plain MIPS32 Release 2 compiler without DSP ASE
instructions. Application developers consume the published toolchain artifact
automatically through the system dependency.

## Build inputs

The compiler is derived from the official Nerves toolchains repository.

- Repository: `https://github.com/nerves-project/toolchains.git`
- Revision: `fa8f8ba3fd3927b2b4fcc23f3d71918e53fec5ba`
- Base package: `nerves_toolchain_mipsel_nerves_linux_musl`
- Custom architecture: `mips32r2`
- Endianness: little-endian
- ABI: MIPS o32
- Floating point: software
- DSP ASE: disabled

The exact upstream source and package name are recorded in `UPSTREAM`. The
custom Crosstool-NG configuration is recorded in `defconfig`.

These files are the checksum inputs for the published toolchain artifact.

## Reproducing the compiler

Create a clean temporary checkout rather than relying on a modified developer
checkout:

```sh
atomcam2_root="$(git rev-parse --show-toplevel)"
build_root="$(mktemp -d)"
toolchains_root="$build_root/toolchains"
package="nerves_toolchain_mipsel_nerves_linux_musl"
revision="$(
  sed -n 's/^revision=//p' "$atomcam2_root/toolchain/UPSTREAM"
)"

git clone \
  https://github.com/nerves-project/toolchains.git \
  "$toolchains_root"

git -C "$toolchains_root" checkout --detach "$revision"

cp \
  "$atomcam2_root/toolchain/defconfig" \
  "$toolchains_root/configs/$package/defconfig"

(
  cd "$toolchains_root"

  make

  bash \
    "$package/build.sh" \
    "$toolchains_root/o/$package"
)
```

The resulting compiler directory is:

```text
o/nerves_toolchain_mipsel_nerves_linux_musl/x-tools/mipsel-nerves-linux-musl
```

Before using it, verify that GCC defaults to `mips32r2` and software floating
point and that both DSP instruction-set options are disabled.
