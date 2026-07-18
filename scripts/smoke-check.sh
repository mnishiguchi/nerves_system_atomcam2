#!/bin/sh
set -eu

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

require_file() {
  if [ -f "$repo_dir/$1" ]; then
    echo "ok: $1"
  else
    echo "missing: $1" >&2
    exit 1
  fi
}

require_executable() {
  require_file "$1"
  if [ -x "$repo_dir/$1" ]; then
    echo "ok: executable $1"
  else
    echo "not executable: $1" >&2
    exit 1
  fi
}

check_script_syntax() {
  shell_file="$1"
  first_line="$(sed -n '1p' "$shell_file")"

  case "$first_line" in
    *bash*) bash -n "$shell_file" ;;
    *) sh -n "$shell_file" ;;
  esac

  echo "ok: syntax ${shell_file#$repo_dir/}"
}

require_grep() {
  pattern="$1"
  file="$2"

  if grep -q "$pattern" "$repo_dir/$file"; then
    echo "ok: $file contains $pattern"
  else
    echo "missing pattern in $file: $pattern" >&2
    exit 1
  fi
}

reject_grep() {
  pattern="$1"
  file="$2"

  if grep -q "$pattern" "$repo_dir/$file"; then
    echo "unexpected pattern in $file: $pattern" >&2
    exit 1
  else
    echo "ok: $file does not contain $pattern"
  fi
}

require_file README.md
require_file fwup.conf
require_file mix.exs
require_file nerves_defconfig
require_file linux-3.10.14.defconfig
require_file busybox.fragment
require_file Config.in
require_file package/Config.in
require_file package/atomcam2-compat-headers/Config.in
require_file package/atomcam2-compat-headers/atomcam2-compat-headers.mk
require_file package/atomcam2-compat-headers/atomcam2-linux-3.10-compat.h
require_file toolchain/mix.exs
require_file toolchain/VERSION
require_file toolchain/UPSTREAM
require_file toolchain/defconfig
require_file toolchain/lib/nerves_toolchain_atomcam2.ex
require_file patches/kernel/0003-linux-3.10-force-gnu89-for-gcc-15.patch
require_file external.desc
require_file external.mk
require_file board/atomcam2/initramfs/init
require_file board/atomcam2/initramfs/bin/busybox
require_file board/atomcam2/initramfs/usr/lib/libc.so
require_file rootfs_overlay/etc/erlinit.config
require_file rootfs_overlay/etc/atomcam2.env
require_executable rootfs_overlay/usr/bin/atomcam2-env
require_executable rootfs_overlay/usr/bin/atomcam2-pre-run
require_executable rootfs_overlay/usr/bin/atomcam2-wifi-driver
require_executable rootfs_overlay/usr/bin/atomcam2-network-check
require_executable scripts/atomcam2-package-flat-sd.sh
require_executable scripts/atomcam2-check-sd-payload.sh
require_executable scripts/atomcam2-check-minimal-ssh-scope.sh
require_executable scripts/build-firmware-log.sh
require_executable scripts/prepare-toolchain-archive.sh
require_executable scripts/release-artifacts.sh
require_file scripts/logging.sh
require_file examples/atomcam2_nerves_app/mix.exs
require_file examples/atomcam2_nerves_app/config/target.exs
require_file examples/atomcam2_nerves_app/rootfs_overlay/etc/iex.exs
require_executable examples/atomcam2_nerves_app/scripts/preserve-final-rootfs.sh
require_file examples/atomcam2_nerves_app/lib/atomcam2_nerves_app/application.ex
network_file="$repo_dir/examples/atomcam2_nerves_app/lib/atomcam2_nerves_app/network.ex"

if [ -e "$network_file" ]; then
  echo "error: $network_file still exists" >&2
  exit 1
else
  echo "ok: $network_file does not exist"
fi

application_lib_dir="$repo_dir/examples/atomcam2_nerves_app/lib"

if grep -R -Fq 'Atomcam2NervesApp.Network' "$application_lib_dir"; then
  echo "error: application source still references Atomcam2NervesApp.Network" >&2
  exit 1
else
  echo "ok: application source does not reference Atomcam2NervesApp.Network"
fi
require_file examples/atomcam2_nerves_app/lib/atomcam2_nerves_app/firmware_update.ex
require_file lib/mix/tasks/atomcam2.install.ex
require_file examples/atomcam2_nerves_app/config/target.exs
require_file docs/worklog/20260715-atomcam2-ping-ssh-bringup.md

require_grep 'config :vintage_net' examples/atomcam2_nerves_app/config/runtime.exs
require_grep 'provisioning_path = "/media/mmc/nerves-provisioning.conf"' examples/atomcam2_nerves_app/config/runtime.exs
require_grep 'nerves-firmware-metadata.conf' examples/atomcam2_nerves_app/config/runtime.exs
require_grep 'Nerves.Runtime.KVBackend.InMemory' examples/atomcam2_nerves_app/config/runtime.exs
require_grep '"wlan0"' examples/atomcam2_nerves_app/config/runtime.exs
require_grep 'wps: false' examples/atomcam2_nerves_app/config/runtime.exs
require_grep ':vintage_net, :mdns_lite, :nerves_ssh' examples/atomcam2_nerves_app/config/target.exs
require_grep 'rootfs_overlay:' examples/atomcam2_nerves_app/config/target.exs
require_grep 'nerves_motd' examples/atomcam2_nerves_app/mix.exs
require_file examples/atomcam2_nerves_app/lib/atomcam2_nerves_app/motd_logo.ex
require_grep 'defmodule Atomcam2NervesApp.MOTDLogo' examples/atomcam2_nerves_app/lib/atomcam2_nerves_app/motd_logo.ex
require_grep 'config_target() != :host' examples/atomcam2_nerves_app/config/runtime.exs
require_grep 'config :nerves_motd' examples/atomcam2_nerves_app/config/runtime.exs
require_grep 'logo: Atomcam2NervesApp.MOTDLogo.render()' examples/atomcam2_nerves_app/config/runtime.exs
iex_file="$repo_dir/examples/atomcam2_nerves_app/rootfs_overlay/etc/iex.exs"

if grep -Fq 'MOTDLogo.render' "$iex_file"; then
  echo "error: $iex_file contains MOTDLogo.render" >&2
  exit 1
else
  echo "ok: $iex_file does not contain MOTDLogo.render"
fi
require_grep 'config :logger, backends: \[RingLogger\]' examples/atomcam2_nerves_app/config/target.exs
require_grep 'protocol: "ssh"' examples/atomcam2_nerves_app/config/target.exs
require_grep 'protocol: "sftp-ssh"' examples/atomcam2_nerves_app/config/target.exs
require_grep 'NervesMOTD.print()' examples/atomcam2_nerves_app/rootfs_overlay/etc/iex.exs
require_grep 'use Toolshed' examples/atomcam2_nerves_app/rootfs_overlay/etc/iex.exs
require_grep 'defmodule Mix.Tasks.Atomcam2.Install' lib/mix/tasks/atomcam2.install.ex
require_grep 'Mix.Task.run("burn", arguments)' lib/mix/tasks/atomcam2.install.ex
require_grep 'deprecated; delegating to mix burn' lib/mix/tasks/atomcam2.install.ex
require_grep 'a.nerves_fw_uuid' scripts/atomcam2-check-sd-payload.sh
require_grep '#define IFA_MAX IFA_FLAGS' package/atomcam2-compat-headers/atomcam2-linux-3.10-compat.h
require_grep 'BR2_PACKAGE_ATOMCAM2_COMPAT_HEADERS=y' nerves_defconfig
require_grep 'atomcam2-linux-3.10-compat.h' mix.exs
require_grep 'artifact_sites:' mix.exs
require_grep 'nerves_toolchain_atomcam2' mix.exs
require_grep 'type: :toolchain' toolchain/mix.exs
require_grep 'artifact_sites:' toolchain/mix.exs
require_grep '"UPSTREAM"' toolchain/mix.exs
require_grep '"defconfig"' toolchain/mix.exs
require_grep 'release-artifacts.sh' toolchain/lib/nerves_toolchain_atomcam2.ex
require_grep 'aliases: aliases()' examples/atomcam2_nerves_app/mix.exs
require_grep 'setup:' examples/atomcam2_nerves_app/mix.exs
require_grep 'ATOMCAM2_SYSTEM_SOURCE' examples/atomcam2_nerves_app/mix.exs
require_grep 'github: @system_repository' examples/atomcam2_nerves_app/mix.exs
require_grep 'nerves: \[compile: true\]' examples/atomcam2_nerves_app/mix.exs
require_grep 'precheck_callback:' examples/atomcam2_nerves_app/config/target.exs
require_grep 'reject_remote_update' examples/atomcam2_nerves_app/lib/atomcam2_nerves_app/firmware_update.ex
reject_grep 'patch-vintage-net-linux-3.10.sh' examples/atomcam2_nerves_app/mix.exs
require_grep 'mix setup' scripts/build-firmware-log.sh
require_grep 'check_command python3' scripts/check-prereqs.sh
require_grep 'CONFIG_BLK_DEV_INITRD=y' linux-3.10.14.defconfig
require_grep 'CONFIG_INITRAMFS_SOURCE="${NERVES_DEFCONFIG_DIR}/board/atomcam2/initramfs"' linux-3.10.14.defconfig
require_grep 'CONFIG_BLK_DEV_LOOP=y' linux-3.10.14.defconfig
require_grep 'CONFIG_NLS_CODEPAGE_437=y' linux-3.10.14.defconfig
require_grep 'CONFIG_FEATURE_MOUNT_LOOP=y' busybox.fragment
require_grep 'CONFIG_JZMMC_V12_MMC1=y' linux-3.10.14.defconfig
require_grep 'CONFIG_JZMMC_V12_MMC1_PC_4BIT=y' linux-3.10.14.defconfig
require_grep 'CONFIG_SQUASHFS_ZLIB=y' linux-3.10.14.defconfig
require_grep 'CONFIG_CMDLINE_OVERRIDE=y' linux-3.10.14.defconfig
require_grep 'CONFIG_AWK=y' busybox.fragment
require_grep 'CONFIG_DD=y' busybox.fragment
require_grep 'CONFIG_DEVMEM=y' busybox.fragment
require_grep 'BR2_TOOLCHAIN_EXTERNAL=y' nerves_defconfig
require_grep 'atomcam2-mips32r2-nerves-toolchain.tar.xz' nerves_defconfig
require_grep 'atomcam2-mips32r2-nerves-toolchain.tar.xz' scripts/prepare-toolchain-archive.sh
require_grep 'NERVES_TOOLCHAIN must point' scripts/prepare-toolchain-archive.sh
require_grep 'mips32r2' scripts/prepare-toolchain-archive.sh
require_grep 'DSP R2 ASE disabled' scripts/prepare-toolchain-archive.sh
reject_grep 'default_toolchain_root' scripts/prepare-toolchain-archive.sh
require_grep 'prepare-toolchain-archive.sh' scripts/check-prereqs.sh
require_grep 'BR2_TOOLCHAIN_EXTERNAL_CUSTOM_MUSL=y' nerves_defconfig
reject_grep 'BR2_TOOLCHAIN_BUILDROOT=y' nerves_defconfig
reject_grep 'BR2_TOOLCHAIN_BUILDROOT_GLIBC=y' nerves_defconfig
reject_grep 'CONFIG_INITRAMFS_SOURCE=""' linux-3.10.14.defconfig
reject_grep '# CONFIG_BLK_DEV_INITRD is not set' linux-3.10.14.defconfig
require_grep 'file-resource nerves-provisioning.conf' fwup.conf

fwup_upgrade_task="$(
  sed -n '/^task upgrade {/,/^}/p' "$repo_dir/fwup.conf"
)"

if [ -n "$fwup_upgrade_task" ]; then
  echo "ok: fwup.conf contains upgrade task"
else
  echo "missing upgrade task in fwup.conf" >&2
  exit 1
fi

for required_line in \
  'require-partition-offset(0, ${BOOT_PART_OFFSET})' \
  'on-resource factory_t31_ZMC6tiIDQN { fat_write(${BOOT_PART_OFFSET}, "factory_t31_ZMC6tiIDQN") }' \
  'on-resource rootfs_hack.squashfs { fat_write(${BOOT_PART_OFFSET}, "rootfs_hack.squashfs") }'; do
  if printf '%s\n' "$fwup_upgrade_task" | grep -Fq -- "$required_line"; then
    echo "ok: fwup upgrade task contains $required_line"
  else
    echo "missing fwup upgrade requirement: $required_line" >&2
    exit 1
  fi
done

for preserved_resource in \
  authorized_keys \
  hostname \
  nerves-provisioning.conf; do
  if printf '%s\n' "$fwup_upgrade_task" |
      grep -Fq -- "on-resource $preserved_resource "; then
    echo "fwup upgrade task replaces preserved resource: $preserved_resource" >&2
    exit 1
  else
    echo "ok: fwup upgrade task preserves $preserved_resource"
  fi
done

require_grep '.nerves' scripts/smoke-check.sh
require_grep '.nerves' scripts/atomcam2-check-minimal-ssh-scope.sh
require_grep 'tmp/log' scripts/logging.sh
require_grep 'logging.sh' scripts/build-firmware-log.sh
require_grep 'logging.sh' scripts/collect-boot-report.sh
require_grep 'refusing to write SD payload to /' scripts/atomcam2-package-flat-sd.sh
require_grep 'output directory must differ from images directory' scripts/atomcam2-package-flat-sd.sh
require_grep 'kernel image is too large for the AtomCam2 boot contract' scripts/atomcam2-package-flat-sd.sh
require_grep 'ATOMCAM2_KERNEL_IMAGE must point to the verified AtomCam2 control kernel' scripts/post-image.sh
require_grep 'b50658eac32b57fdcb20383d82a54e6439acd7a3f7e9cb8b43edf4a4b89b03bc' scripts/post-image.sh
require_grep 'ATOMCAM2_KERNEL_IMAGE' scripts/release-artifacts.sh
require_grep 'unexpected AtomCam2 control kernel SHA256' scripts/release-artifacts.sh
require_grep 'toolchain/VERSION' scripts/release-artifacts.sh
require_grep 'checksum_paths' scripts/release-artifacts.sh
require_grep '\-\-kernel-image' scripts/atomcam2-package-flat-sd.sh
require_grep '\-\-rootfs-image' scripts/atomcam2-package-flat-sd.sh
require_grep 'post_processing_script' examples/atomcam2_nerves_app/config/target.exs
require_grep 'rootfs_hack.final.squashfs' examples/atomcam2_nerves_app/scripts/preserve-final-rootfs.sh
require_grep 'source and mount directories must differ' scripts/install-sd-files.sh
require_grep 'cannot resolve images directory' scripts/atomcam2-package-flat-sd.sh
require_grep 'cannot resolve source directory' scripts/install-sd-files.sh
require_grep 'cannot resolve mount directory' scripts/collect-boot-report.sh
require_grep 'NERVES_DEFCONFIG_DIR/package/Config.in' Config.in
require_grep 'NERVES_DEFCONFIG_DIR)/package' external.mk
reject_grep 'BR2_EXTERNAL_NERVES_SYSTEM_ATOMCAM2_PATH' Config.in
reject_grep 'BR2_EXTERNAL_NERVES_SYSTEM_ATOMCAM2_PATH' external.mk
reject_grep 'BR2_PACKAGE_ATOMCAM2_FIRST_SSH' nerves_defconfig
reject_grep 'atomcam2-first-ssh' package/Config.in
reject_grep 'env | sort' rootfs_overlay/usr/bin/atomcam2-env
reject_grep 'head -n' rootfs_overlay/usr/bin/atomcam2-network-check
reject_grep 'tr -' rootfs_overlay/usr/bin/atomcam2-pre-run
reject_grep 'atomcam2-pre-run-entered.env' rootfs_overlay/usr/bin/atomcam2-pre-run
reject_grep 'atomcam2-wifi-driver-entered.env' rootfs_overlay/usr/bin/atomcam2-wifi-driver
reject_grep 'atomcam2-wifi-driver.log' rootfs_overlay/usr/bin/atomcam2-wifi-driver
reject_grep 'atomcam2-erlinit.log' board/atomcam2/post-build.sh
reject_grep 'ATOMCAM2_WIFI_DRIVER_LOG' rootfs_overlay/etc/atomcam2.env

for symlink_path in \
  board/atomcam2/initramfs/bin/sh \
  board/atomcam2/initramfs/bin/mount \
  board/atomcam2/initramfs/sbin/switch_root \
  board/atomcam2/initramfs/lib/ld-musl-mipsel-sf.so.1; do
  if [ -L "$repo_dir/$symlink_path" ]; then
    echo "ok: symlink $symlink_path"
  else
    echo "not a symlink: $symlink_path" >&2
    exit 1
  fi
done

find "$repo_dir" \
  -path '*/.git' -prune -o \
  -path '*/.nerves' -prune -o \
  -path '*/_build' -prune -o \
  -path '*/deps' -prune -o \
  -path '*/target' -prune -o \
  -path "$repo_dir/tmp" -prune -o \
  -path '*/vendor' -prune -o \
  -name '*.log' -prune -o \
  -name '*.dump' -prune -o \
  \( -name '*.sh' -o -path '*/usr/bin/atomcam2-*' -o -path '*/initramfs/init' \) \
  -type f -print | while IFS= read -r shell_file; do
  check_script_syntax "$shell_file"
done

require_file examples/atomcam2_nerves_app/lib/atomcam2_nerves_app/discovery.ex
require_grep 'Atomcam2NervesApp.Discovery.advertise()' examples/atomcam2_nerves_app/lib/atomcam2_nerves_app/application.ex
require_grep 'protocol: "nerves-device"' examples/atomcam2_nerves_app/lib/atomcam2_nerves_app/discovery.ex
require_grep '"serial=#{Nerves.Runtime.serial_number()}"' examples/atomcam2_nerves_app/lib/atomcam2_nerves_app/discovery.ex
require_grep '"version=#{application_version()}"' examples/atomcam2_nerves_app/lib/atomcam2_nerves_app/discovery.ex
require_grep 'port: 0' examples/atomcam2_nerves_app/lib/atomcam2_nerves_app/discovery.ex

"$repo_dir/scripts/atomcam2-check-minimal-ssh-scope.sh" "$repo_dir"

require_grep 'nerves_time' examples/atomcam2_nerves_app/mix.exs
require_grep 'time_file: "/media/mmc/.nerves_time"' examples/atomcam2_nerves_app/config/runtime.exs
require_grep 'await_initialization_timeout: 5_000' examples/atomcam2_nerves_app/config/runtime.exs

require_grep 'system_dir: "/media/mmc/nerves_ssh"' examples/atomcam2_nerves_app/config/runtime.exs
require_grep 'user_dir: "/media/mmc/nerves_ssh/default_user"' examples/atomcam2_nerves_app/config/runtime.exs
require_file examples/atomcam2_nerves_app/lib/atomcam2_nerves_app/time_sync.ex
require_grep 'Atomcam2NervesApp.TimeSync' examples/atomcam2_nerves_app/lib/atomcam2_nerves_app/application.ex
require_grep 'VintageNet.subscribe(@connection_property)' examples/atomcam2_nerves_app/lib/atomcam2_nerves_app/time_sync.ex
require_grep 'NervesTime.restart_ntpd()' examples/atomcam2_nerves_app/lib/atomcam2_nerves_app/time_sync.ex
