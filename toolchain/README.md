# Atom Cam 2 Nerves toolchain package

This package describes the prebuilt MIPS32R2 soft-float toolchain used by
`nerves_system_atomcam2`.

The compiler is built outside Nerves because the stock MIPSEL toolchain enables
DSP ASE instructions that the Ingenic T31 cannot execute. System maintainers
package and publish the validated compiler with `scripts/release-artifacts.sh`.
Application developers consume the published artifact automatically through the
system dependency.
