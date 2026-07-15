# 20260713 AtomCam2 toolchain DSP ASE investigation

## Result

The first Nerves userspace could not run reliably on the Atom Cam 2 because the stock MIPSEL Nerves toolchain targeted the `24kec` processor profile and enabled the MIPS DSP Application-Specific Extension.

The generated musl runtime contained DSP instructions such as:

```asm
lwx
lhx
```

The Ingenic T31 processor raised `SIGILL` when dynamically linked programs reached those instructions.

A dedicated Nerves toolchain targeting plain MIPS32 Release 2, soft-float, and no DSP ASE resolved the dynamic userspace failure.

This was a confirmed prerequisite for the later ping and SSH milestone. It was not itself a Wi-Fi configuration problem.

## Initial symptom

The firmware built successfully, but the device did not publish `nerves.local` or accept SSH.

At that point, the failure could have been anywhere in this chain:

```text
U-Boot
-> kernel
-> initramfs
-> rootfs mount
-> switch_root
-> dynamic loader
-> /sbin/init
-> Erlang VM
-> application
-> Wi-Fi
-> DHCP
-> mDNS
-> SSH
```

The investigation therefore tested one boundary at a time instead of treating the missing hostname as proof of a network failure.

## Known-good control

The same camera and MicroSD card successfully booted `atomcam_tools` and became reachable through its normal network services.

This proved the basic hardware path:

- Camera hardware
- MicroSD card and FAT partition
- U-Boot loading `factory_t31_ZMC6tiIDQN`
- Vendor kernel and initramfs
- Wi-Fi hardware in the vendor environment

The remaining problem was specific to the Nerves kernel or userspace.

## Fault isolation

### Static userspace worked

Small statically linked MIPS programs reached `main()` and wrote diagnostic breadcrumbs.

This proved that the processor could execute the selected MIPS32R2 instruction set and that the kernel could enter userspace.

### Dynamic userspace failed

Dynamically linked probes failed before reaching their first application breadcrumb.

Both PIE and non-PIE variants failed, so PIE was not the differentiating factor.

### `rdhwr` was not the blocker

A direct probe of the MIPS thread-pointer instruction completed successfully.

This ruled out the early suspicion that the vendor Linux 3.10 kernel could not support the instruction used by musl TLS setup.

### The actual signal was `SIGILL`

A small parent process captured the child termination signal. Dynamic probes consistently died with an illegal instruction rather than a missing loader, segmentation fault, or ordinary process exit.

### ELF attributes exposed DSP ASE

Inspection of the stock runtime showed the `24kec` target and DSP ASE attributes.

Disassembly of musl identified DSP instructions in code reached during dynamic process startup.

This connected the `SIGILL` evidence to a concrete toolchain property.

## Root cause

The Buildroot target configuration and the external Nerves toolchain configuration were not equivalent.

Changing the system architecture to MIPS32R2 did not rebuild or replace the stock external toolchain's DSP-enabled musl runtime.

The effective relationship was:

```text
Buildroot target settings
!=
architecture of the external toolchain runtime
```

As long as the root filesystem used the stock `24kec` runtime, dynamically linked Nerves userspace remained incompatible with the Ingenic T31.

## Fix

A dedicated external Nerves toolchain was built with these target properties:

```text
Architecture: MIPS32 Release 2
Endianness: little-endian
ABI: O32
Floating point: soft-float
C library: musl
DSP ASE: disabled
```

The rebuilt dynamic test matrix then completed successfully:

```text
dynamic_pie_exit_status=0
dynamic_no_pie_exit_status=0
```

Both programs reached `main()`.

The final Nerves system, Buildroot packages, native ports, and runtime libraries must all use this same toolchain. Copying only `libc.so` is not a valid permanent solution.

## Ruled-out hypotheses

The following were investigated but were not the dynamic runtime root cause:

- MicroSD hardware or partition layout
- U-Boot loading the kernel
- Root filesystem compression by itself
- `switch_root`
- PIE versus non-PIE
- The MIPS `rdhwr` instruction
- Stale `.nerves` state
- Merely changing Buildroot's MIPS CPU selection

Some of these still required independent cleanup, but none explained the observed `SIGILL`.

## Reusable investigation methods

The most useful techniques were:

- Start with a known-good hardware control.
- Separate kernel and userspace by using the known-good vendor kernel with the Nerves root filesystem.
- Prefer tiny static probes for early userspace.
- Use a writable diagnostic root filesystem when normal logging is unavailable.
- Capture fatal child signals explicitly.
- Compare PIE and non-PIE rather than assuming one is responsible.
- Inspect ELF attributes and disassembly, not only compiler command-line flags.
- Keep Buildroot configuration and external toolchain configuration conceptually separate.

## Follow-up boundary

After the custom non-DSP toolchain was integrated, the next investigations could move to:

```text
application-merged rootfs
-> erlinit and Erlang release
-> SDIO and vendor Wi-Fi driver
-> VintageNet
-> wpa_supplicant
-> DHCP, mDNS, and SSH
```

Those stages are documented in the July 14 and July 15 worklogs.
