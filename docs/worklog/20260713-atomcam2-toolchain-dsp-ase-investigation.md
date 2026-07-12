# AtomCam2 Nerves firmware boot investigation

## Summary

This worklog records the investigation into why the initial `nerves_system_atomcam2` firmware did not reach the Nerves runtime on Atom Cam 2.

The final confirmed blocker was not the SD card, bootloader, kernel loading, root filesystem mounting, `switch_root`, PIE, or the MIPS thread-pointer instruction.

The firmware failed because the standard Nerves MIPSEL toolchain targeted the MIPS `24kec` processor profile. That profile enables the MIPS DSP Application-Specific Extension.

Its musl `libc.so` therefore contained DSP instructions such as:

```asm
lwx
lhx
```

The Ingenic T31 processor in Atom Cam 2 did not execute these instructions successfully and raised `SIGILL`.

A custom Nerves toolchain targeting plain MIPS32R2 soft-float, without DSP ASE, resolved the dynamic userspace failure.

The final dynamic execution test produced:

```text
stage=matrix_runner_entered
dynamic_pie_starting
dynamic_pie_exit_status=0
dynamic_no_pie_starting
dynamic_no_pie_exit_status=0
stage=matrix_complete
```

Both dynamically linked probes successfully reached `main()`:

```text
stage=dynamic_pie_entered
stage=dynamic_no_pie_entered
```

This confirms that the custom non-DSP toolchain and its musl runtime operate correctly on Atom Cam 2.

At this point, the full Nerves firmware still needs to be rebuilt and tested with the custom toolchain.

## Objective

The initial MVP goal was intentionally small:

- Boot a Nerves firmware on Atom Cam 2.
- Connect to the configured 2.4 GHz Wi-Fi network.
- Resolve `nerves.local`.
- Connect through SSH.

Camera services, RTSP, the vendor application, WebUI, Samba, and other higher-level features were deferred.

## Initial symptoms

The firmware built successfully:

```text
Firmware built successfully
```

The generated firmware metadata identified the expected target:

```text
meta-platform=atomcam2
meta-architecture=mipsel
```

However, after writing it to an SD card and booting the camera:

```sh
ping nerves.local
```

failed with:

```text
Name or service not known
```

No SSH service or mDNS hostname appeared.

At this point, several independent stages could have been failing:

```text
U-Boot
-> SD card detection
-> kernel loading
-> initramfs execution
-> root filesystem mounting
-> switch_root
-> /sbin/init
-> dynamic loader
-> erlinit
-> Erlang VM
-> application startup
-> Wi-Fi
-> mDNS
```

The investigation therefore focused on proving each stage separately instead of repeatedly rebuilding the complete firmware.

## Initial build compatibility fixes

Before runtime investigation, several build-time problems had to be resolved.

### Linux 3.10 and modern GCC

The vendor Linux 3.10.14 source did not compile cleanly with the current host compiler because modern GCC defaults to newer C language behavior.

The kernel build was adjusted to use:

```text
-std=gnu89
```

This retained compatibility with the old kernel source.

### Minimal Nerves application dependencies

The sample application was kept intentionally small and used direct dependencies rather than `nerves_pack`:

- `nerves_runtime`
- `nerves_ssh`
- `mdns_lite`
- `vintage_net`
- `vintage_net_wifi`

This reduced unrelated variables during bring-up.

### MIPS native dependency flags

The initial target metadata used MIPS32R5 flags. That caused incompatibilities when compiling native dependencies.

The application-side environment was temporarily reduced to a conservative MIPS target:

```elixir
"TARGET_CPU" => "mips32",
"TARGET_GCC_FLAGS" => "-EL -mabi=32"
```

This solved native dependency compilation, but it did not control the architecture of the prebuilt toolchain’s musl runtime.

### VintageNet compatibility with Linux 3.10 headers

VintageNet expected `IFA_FLAGS`, which was absent from the old Linux headers used by the target.

A local compatibility script added:

```c
#ifndef IFA_FLAGS
#define IFA_FLAGS 8
#endif
```

to the relevant VintageNet source before compilation.

This was a build compatibility adjustment and was unrelated to the eventual runtime `SIGILL`.

## Establishing a known-good control

Before debugging Nerves internals, we needed to prove that the physical boot path worked.

The same camera and SD card were tested with `atomcam_tools`.

The result was successful:

```sh
ping atomcam.local
```

returned responses, and:

```sh
curl -I http://atomcam.local
```

returned:

```text
HTTP/1.1 200 OK
Server: lighttpd/1.4.39
```

This control test proved that the following components were working:

- Atom Cam 2 hardware
- SD card
- FAT32 filesystem
- MBR partition layout
- SD card detection by U-Boot
- loading `factory_t31_ZMC6tiIDQN`
- the basic kernel and initramfs boot path
- network hardware and Wi-Fi in the vendor environment

This significantly narrowed the search space.

## Comparing kernel images

The Nerves kernel image and the known-good `atomcam_tools` kernel had compatible U-Boot metadata:

```text
Architecture: MIPS
Compression: LZMA
Load address: 0x80010000
```

However, their entry addresses and sizes differed.

The Nerves kernel used an entry address similar to:

```text
0x8037f550
```

The known-good kernel used:

```text
0x803736d0
```

This difference alone did not prove an error, but it reinforced the decision to use the known-good kernel during root filesystem investigation.

## Initramfs investigation

The first Nerves initramfs contained an `/init` script but lacked the commands required to execute it reliably.

A minimal BusyBox-based initramfs was added with commands including:

```text
/bin/busybox
/bin/sh
/bin/mount
/bin/mkdir
/bin/cat
/bin/grep
/bin/sleep
/sbin/switch_root
```

The generated kernel initramfs archive was verified directly:

```sh
usr/initramfs_data.cpio
```

and confirmed to contain:

```text
init
bin/busybox
bin/sh
sbin/switch_root
```

Despite this, no early initramfs breadcrumb appeared on the SD card.

At that point, it was still unclear whether:

- the Nerves kernel was being loaded,
- the initramfs was running,
- the SD partition was visible,
- or the root filesystem was being mounted.

## Hybrid boot strategy

To reduce the number of unknowns, the known-good `atomcam_tools` kernel and initramfs were combined with a Nerves root filesystem.

The intended boot chain became:

```text
known-good AtomCam2 kernel and initramfs
-> Nerves root filesystem
-> Nerves /sbin/init
```

This allowed the investigation to bypass uncertainty around the custom kernel while testing the Nerves userspace.

## SquashFS compression mismatch

The first hybrid root filesystem used XZ compression:

```text
Squashfs filesystem, version 4.0, xz compressed
```

The known-good `atomcam_tools` root filesystem used zlib compression:

```text
Squashfs filesystem, version 4.0, zlib compressed
```

The Nerves Buildroot configuration was changed from XZ to gzip/zlib compression.

After rebuilding:

```text
Squashfs filesystem, version 4.0, zlib compressed
```

This made the filesystem format compatible with the known-good boot path.

However, networking still did not start, and no `/sbin/init` breadcrumb appeared.

This was a real compatibility issue, but it was not the final runtime blocker.

## Problems with shell-based breadcrumbs

A temporary `/sbin/init` wrapper attempted to write:

```text
/media/mmc/atomcam2-sbin-init.env
```

and then execute:

```sh
exec /usr/sbin/erlinit
```

Inspection of the root filesystem showed that `/usr/sbin/erlinit` did not exist.

The original Nerves init binary was actually installed at:

```text
/sbin/init
```

The overlay had replaced it.

The wrapper was changed to preserve the original binary as:

```text
/sbin/init.real
```

Even after this correction, no shell-based breadcrumb appeared.

This taught us an important lesson: a shell wrapper is not a reliable early diagnostic when the failure may occur in the shell’s own dynamic loader.

## Switching to an ext2 root filesystem

The root filesystem was converted to a writable ext2 image:

```text
rootfs_hack.ext2
```

This provided two advantages:

- The known-good initramfs already supported it.
- A program running as `/sbin/init` could write diagnostic files directly into `/`.

This avoided dependence on whether `/media/mmc` had been moved or mounted at the expected location.

## Static `/sbin/init` probe

A tiny statically linked MIPS executable was installed as `/sbin/init`.

It wrote:

```text
stage=static_init_entered
result=rootfs_mounted_switch_root_completed
```

into the ext2 root filesystem.

After booting, the file was present.

This proved the following chain conclusively:

```text
U-Boot loaded the known-good kernel
-> kernel started
-> initramfs started
-> rootfs_hack.ext2 mounted
-> switch_root succeeded
-> /sbin/init executed
-> statically linked MIPS userspace ran
```

This eliminated the following as root causes:

- SD card layout
- boot filename
- kernel loading
- root filesystem discovery
- ext2 support
- root filesystem mounting
- `switch_root`
- generic MIPS instruction execution

The failure had to be inside the normal dynamically linked Nerves userspace.

## Inspecting the Nerves userspace

The ext2 root filesystem contained:

```text
/sbin/init.real
/bin/busybox
/lib/ld-musl-mipsel-sf.so.1
/usr/lib/libc.so
```

Both `/sbin/init.real` and BusyBox were:

```text
ELF 32-bit LSB
MIPS32r2
dynamically linked
soft-float
```

They requested:

```text
/lib/ld-musl-mipsel-sf.so.1
```

That loader existed as a link to:

```text
/usr/lib/libc.so
```

Therefore, this was not simply a missing-loader or missing-file problem.

## Minimal dynamic BusyBox probe

A static `/sbin/init` wrote:

```text
stage=before_busybox_exec
```

and then called:

```c
execve("/bin/busybox", ...)
```

The first marker appeared, but BusyBox’s own marker did not:

```text
stage=before_busybox_exec
```

```text
atomcam2-busybox-ok.env: missing
```

The static process did not record an `execve` error, which meant `execve()` had succeeded from the parent process’s perspective.

The newly loaded dynamic process failed before executing its shell command.

This isolated the failure to:

```text
kernel dynamic ELF loading
or
musl startup
or
early BusyBox runtime initialization
```

## PIE and non-PIE matrix

To determine whether the old kernel had a PIE-specific issue, two minimal dynamically linked executables were created:

- PIE
- non-PIE

A statically linked PID 1 runner launched each child and recorded its wait status.

The result was:

```text
stage=matrix_runner_entered
dynamic_pie_starting
dynamic_pie_signal=4
dynamic_no_pie_starting
dynamic_no_pie_signal=4
stage=matrix_complete
```

Signal 4 is:

```text
SIGILL
```

Both PIE and non-PIE binaries failed before reaching `main()`.

This ruled out a PIE-only compatibility issue.

It also showed that the common failing component was the dynamic musl startup path.

## Testing the MIPS thread-pointer instruction

musl on MIPS commonly uses:

```asm
rdhwr $3, $29
```

to obtain the thread pointer.

A dedicated static probe executed this exact instruction in a child process.

The result was:

```text
stage=rdhwr_probe_entered
rdhwr_exit_status=0
stage=rdhwr_probe_complete
```

This disproved the hypothesis that the vendor kernel lacked working `rdhwr` handling.

No kernel patch for `rdhwr` was required.

## Capturing the exact illegal instruction

A static PID 1 tracer used `ptrace` to launch the dynamically linked non-PIE probe.

It recorded:

- stop signals
- EPC
- Cause register
- BadVAddr
- the faulting instruction
- the child process memory map

The result was:

```text
stage=tracer_entered
initial_stop_signal=23
stop_signal=5
stage=exec_trap
stop_signal=4
stage=sigill_captured
epc=0x772041fc
badvaddr=0x7716f014
cause=0x80800028
fault_address=0x77204200
fault_instruction=0x7d68400a
stage=trace_complete
```

The child memory map showed:

```text
7716a000-7723e000 r-xp ... /usr/lib/libc.so
```

Therefore, the fault occurred inside `libc.so`.

The calculated library offset was:

```text
0x77204200 - 0x7716a000 = 0x0009a200
```

Disassembly at that offset showed:

```asm
9a1fc: 10000006  b       9a218
9a200: 7d68400a  lwx     t0,t0(t3)
```

The Cause register indicated that the illegal instruction occurred in the branch delay slot, so the tracer correctly used `EPC + 4` as the actual fault address.

Additional nearby instructions included:

```asm
lwx
lhx
```

The fault was therefore an unsupported indexed-load instruction in musl, not a generic loader failure.

## ELF attributes revealed DSP ASE

Running:

```sh
mipsel-nerves-linux-musl-readelf -A libc.so
```

reported:

```text
ISA: MIPS32r2
FP ABI: Soft float
ISA Extension: None
ASEs:
        DSP ASE
```

This was the decisive metadata.

The dynamic runtime was built with MIPS DSP instructions enabled.

A compiler experiment confirmed the relationship.

A normal indexed array access compiled without DSP used ordinary instructions such as:

```asm
sll
addu
lw
```

The same code built with:

```text
-mdsp
```

used:

```asm
lwx
```

This matched the exact instruction observed in the runtime crash.

## Why changing `nerves_defconfig` was insufficient

The original system configuration included:

```text
BR2_MIPS_CPU_MIPS32R5=y
```

This was not the correct user-selectable Buildroot architecture symbol.

It was replaced with:

```text
BR2_mipsel=y
BR2_mips_xburst=y
```

The generated Buildroot configuration then correctly reported:

```text
BR2_GCC_TARGET_ARCH="mips32r2"
BR2_MIPS_CPU_MIPS32R2=y
BR2_mips_xburst=y
BR2_MIPS_SOFT_FLOAT=y
BR2_MIPS_NAN_LEGACY=y
BR2_MIPS_OABI32=y
```

The compiler also reported:

```text
_MIPS_ARCH="mips32r2"
__mips_isa_rev=2
```

However, the rebuilt `libc.so` still contained DSP ASE instructions.

The reason was that the Nerves system used an external prebuilt Nerves toolchain.

Buildroot could use MIPS32R2 for packages compiled inside the system build, but it did not rebuild the external toolchain’s musl runtime.

The DSP-enabled `libc.so` came from the external Nerves toolchain and remained unchanged.

## Root cause in the standard Nerves MIPSEL toolchain

The standard Nerves MIPSEL toolchain configuration used:

```text
CT_ARCH_ARCH="24kec"
```

The MIPS `24kec` processor target enables the DSP ASE.

As a result, the toolchain’s:

- musl dynamic loader
- `libc.so`
- compiler runtime
- potentially other target libraries

could contain DSP instructions.

Atom Cam 2’s Ingenic T31 processor executed the basic MIPS32R2 instruction set used by our static probes, but it raised `SIGILL` when the dynamic musl runtime executed `lwx`.

The complete failure path was:

```text
/sbin/init or BusyBox is loaded
-> kernel accepts the ELF
-> musl begins runtime initialization
-> libc executes DSP ASE instruction lwx
-> T31 raises reserved-instruction exception
-> process receives SIGILL
-> userspace dies before main
-> erlinit never starts
-> Erlang VM never starts
-> VintageNet never starts
-> nerves.local never appears
```

## Building a custom Nerves toolchain

The Nerves toolchains repository was cloned locally.

The MIPSEL toolchain definition was changed from:

```text
CT_ARCH_ARCH="24kec"
```

to:

```text
CT_ARCH_ARCH="mips32r2"
```

The rest of the important target properties remained:

```text
little-endian
MIPS
soft-float
musl
O32 ABI
```

Host build dependencies discovered during toolchain generation included:

```text
texinfo
libtool-bin
```

After installing them, the generated toolchain project confirmed:

```text
CT_ARCH_ARCH="mips32r2"
```

The custom toolchain was then built successfully.

## Verifying the custom toolchain

The new custom musl runtime reported:

```text
ISA: MIPS32r2
FP ABI: Soft float
ISA Extension: None
ASEs:
        None
```

This was the required distinction from the original toolchain:

```text
Original:
ASEs:
        DSP ASE

Custom:
ASEs:
        None
```

The custom compiler produced dynamic PIE and non-PIE test executables with:

```text
ISA: MIPS32r2
FP ABI: Soft float
ISA Extension: None
ASEs:
        None
```

The custom `libc.so` was copied into the ext2 root filesystem so that the test executables and runtime came from the same toolchain.

## Final runtime proof

The dynamic execution matrix was repeated using:

- custom MIPS32R2 static runner
- custom MIPS32R2 PIE probe
- custom MIPS32R2 non-PIE probe
- custom non-DSP musl `libc.so`

The result was:

```text
stage=matrix_runner_entered
dynamic_pie_starting
dynamic_pie_exit_status=0
dynamic_no_pie_starting
dynamic_no_pie_exit_status=0
stage=matrix_complete
```

The application markers also appeared:

```text
stage=dynamic_pie_entered
stage=dynamic_no_pie_entered
```

This proves:

```text
known-good AtomCam2 kernel
-> rootfs mount
-> switch_root
-> static MIPS32R2 userspace
-> custom musl dynamic loader
-> dynamic PIE process
-> dynamic non-PIE process
-> application main
```

The custom non-DSP toolchain resolved the observed dynamic userspace failure.

## Investigation techniques that were particularly useful

## Establish a known-good control first

Testing `atomcam_tools` on the same camera and SD card prevented us from blaming hardware, partitioning, U-Boot, or Wi-Fi prematurely.

A control image is especially valuable when porting Nerves to unsupported hardware.

## Reduce the boot chain one boundary at a time

Rather than testing the complete firmware repeatedly, we isolated boundaries:

```text
kernel
rootfs
switch_root
static init
dynamic init
libc
application main
networking
```

Each successful probe removed several possible causes.

## Prefer statically linked probes for early userspace

A shell script was not sufficient because `/bin/sh` itself depended on the failing dynamic loader.

A tiny static `/sbin/init` could run independently of:

- musl dynamic linking
- BusyBox
- erlinit
- Erlang
- VintageNet
- mDNS

This was the turning point in the investigation.

## Use a writable root filesystem for breadcrumbs

Writing into ext2 eliminated uncertainty around whether the FAT partition had been mounted or moved to `/media/mmc`.

The diagnostic output remained available after power-off and could be inspected from the host.

## Use child processes to capture fatal signals

A process that replaces itself with `execve()` cannot report a later crash.

A static parent using:

```c
fork()
execve()
waitpid()
```

could record whether the child:

- exited normally,
- failed `execve`,
- or received a signal.

This revealed `SIGILL`.

## Compare PIE and non-PIE explicitly

Testing both prevented us from incorrectly blaming ET_DYN or old-kernel PIE behavior.

Both failed identically, so PIE was not the important variable.

## Test suspected instructions directly

The `rdhwr` hypothesis was plausible, but a minimal direct probe disproved it quickly.

This prevented an unnecessary kernel patch.

## Use `ptrace` to capture the actual fault

The static tracer converted a vague `SIGILL` into concrete evidence:

```text
fault address
fault instruction
library mapping
library offset
```

This made it possible to identify the exact `lwx` instruction in musl.

## Inspect ELF attributes, not only compiler defaults

The compiler reported MIPS32R2, but the library itself reported:

```text
DSP ASE
```

The ELF metadata described the actual generated binary more accurately than assumptions based on architecture names.

Useful commands included:

```sh
readelf -A
readelf -h
objdump -d
nm -D -n
file
```

## Distinguish Buildroot target configuration from external toolchain configuration

Changing:

```text
BR2_mips_xburst=y
```

affected packages built by Buildroot, but it could not rewrite the prebuilt external musl runtime.

When a system uses an external toolchain, its architecture and ABI choices must be inspected separately.

## Keep hypotheses falsifiable

Several plausible hypotheses were discarded through direct tests:

- SD card failure
- incorrect partition layout
- kernel not loading
- initramfs not running
- unsupported SquashFS alone
- `switch_root` failure
- missing dynamic loader
- PIE incompatibility
- broken `rdhwr`
- generic MIPS32R2 incompatibility

Each hypothesis was converted into a test with a clear expected result.

## False leads and corrections

### Root filesystem compression

The XZ versus zlib difference was worth correcting because the known-good boot path used zlib.

However, changing compression did not resolve the dynamic runtime failure.

### `/usr/sbin/erlinit`

The temporary wrapper assumed that the real Nerves init lived at:

```text
/usr/sbin/erlinit
```

The generated rootfs instead installed the real init at:

```text
/sbin/init
```

Replacing `/sbin/init` without preserving it temporarily removed the real Nerves init.

### Shell breadcrumbs

The absence of a shell breadcrumb originally looked like evidence that `/sbin/init` had not been reached.

In reality, the shell itself could not start because its dynamic musl runtime crashed with `SIGILL`.

### PIE

The fact that Nerves executables were PIE made PIE compatibility a plausible suspect.

The dynamic matrix proved both PIE and non-PIE failed with the same signal.

### `rdhwr`

MIPS musl uses `rdhwr`, and old vendor kernels sometimes differ from upstream behavior.

The direct `rdhwr` probe exited successfully, so this was not the blocker.

### Buildroot MIPS32R2 configuration

Correcting the Buildroot architecture was necessary, but it did not replace the external toolchain’s DSP-enabled musl.

This distinction was important:

```text
Buildroot architecture
!=
external toolchain architecture
```

## Current status

Confirmed working:

- Atom Cam 2 SD boot
- known-good kernel and initramfs
- ext2 root filesystem mounting
- `switch_root`
- static MIPS32R2 userspace
- `rdhwr`
- custom non-DSP musl dynamic loading
- custom dynamic PIE executable
- custom dynamic non-PIE executable

Not yet confirmed:

- full `nerves_system_atomcam2` built with the custom toolchain
- real Nerves `/sbin/init`
- erlinit
- Erlang VM
- application release
- Wi-Fi through VintageNet
- mDNS through `mdns_lite`
- SSH through `nerves_ssh`
- the custom Nerves kernel path

## Recommended next steps

### Integrate the custom toolchain

Connect the locally built MIPS32R2 non-DSP toolchain to `nerves_system_atomcam2`.

The system must use the custom toolchain for:

- musl
- dynamic loader
- compiler runtime
- Buildroot packages
- native application dependencies

Avoid copying only `libc.so` as a permanent fix. All runtime components should come from one consistent toolchain.

### Perform a fully clean system build

Remove cached artifacts that may still contain the stock `24kec` toolchain output.

Rebuild:

- the Nerves system
- Buildroot packages
- root filesystem
- application native dependencies
- final firmware

### Verify the final rootfs

Before booting, inspect the final firmware rootfs:

```sh
readelf -A usr/lib/libc.so
```

Expected:

```text
ISA: MIPS32r2
FP ABI: Soft float
ASEs:
        None
```

Check important executables as well:

```text
/sbin/init
/bin/busybox
Erlang runtime binaries
native NIFs and ports
```

### Repeat the hybrid boot first

Before switching back to the custom kernel, use:

```text
known-good atomcam_tools kernel
+
final Nerves rootfs built with custom toolchain
```

This will isolate userspace integration from kernel integration.

Expected progression:

```text
/sbin/init
-> erlinit
-> Erlang VM
-> application
-> Wi-Fi
-> mDNS
-> SSH
```

### Test the MVP endpoints

```sh
ping nerves.local
ssh nerves.local
```

If mDNS fails, also inspect the DHCP lease or router client list and test SSH by IP address.

### Test the custom kernel separately

Once the userspace works with the known-good kernel, replace only the kernel with the Nerves-built kernel.

This preserves a clear boundary:

```text
userspace proven first
kernel proven second
```

### Remove temporary diagnostics

After the full firmware boots:

- remove static init probes
- remove ext2 debugging images
- remove temporary `/sbin/init` wrappers
- remove copied custom `libc.so`
- remove signal tracers
- retain reusable diagnostic scripts only if they are documented and clearly separated from production code

## Architectural decision suggested by this investigation

The AtomCam2 system should use a dedicated Nerves toolchain rather than the stock `nerves_toolchain_mipsel_nerves_linux_musl`.

The required target properties are:

```text
Architecture: MIPS32R2
Endianness: little-endian
ABI: O32
Floating point: soft-float
C library: musl
DSP ASE: disabled
```

This custom toolchain is not merely an optimization choice. It is required for runtime correctness on the Ingenic T31 processor used by Atom Cam 2.

## Final conclusion

The original firmware did not fail because Nerves could not boot from the Atom Cam 2 SD card.

It failed because the stock Nerves MIPSEL userspace was compiled for a processor profile that included DSP instructions unsupported by the target at runtime.

The investigation proved this by progressively reducing the boot path, executing static probes, observing `SIGILL` in dynamic children, capturing the exact fault through `ptrace`, mapping it into musl `libc.so`, identifying the `lwx` instruction, and comparing the ELF DSP attributes of the original and custom toolchains.

The custom MIPS32R2 soft-float toolchain without DSP ASE successfully ran both PIE and non-PIE dynamically linked programs on Atom Cam 2.

This gives us a reliable foundation for the next phase: rebuilding and booting the complete Nerves firmware with the custom toolchain.
