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
require_executable board/atomcam2/boot-manager/init
require_file board/atomcam2/initramfs/bin/busybox
require_file board/atomcam2/initramfs/usr/lib/libc.so
require_file rootfs_overlay/etc/erlinit.config
require_file rootfs_overlay/etc/atomcam2.env
require_executable rootfs_overlay/usr/bin/atomcam2-env
require_executable rootfs_overlay/usr/bin/atomcam2-pre-run
require_executable rootfs_overlay/usr/bin/atomcam2-wifi-driver
require_executable rootfs_overlay/usr/bin/atomcam2-network-check
require_executable scripts/atomcam2-build-boot-manager.sh
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
reject_grep 'nerves-firmware-metadata.conf' examples/atomcam2_nerves_app/config/runtime.exs
require_grep 'Nerves.Runtime.KVBackend.InMemory' examples/atomcam2_nerves_app/config/target.exs
require_grep 'a.nerves_fw_product' examples/atomcam2_nerves_app/config/target.exs
require_grep 'a.nerves_fw_version' examples/atomcam2_nerves_app/config/target.exs
require_grep 'a.nerves_fw_platform' examples/atomcam2_nerves_app/config/target.exs
require_grep 'a.nerves_fw_architecture' examples/atomcam2_nerves_app/config/target.exs
require_grep '"a.nerves_fw_application_part0_devpath" => "/dev/rootdisk0p4"' examples/atomcam2_nerves_app/config/target.exs
require_grep '"a.nerves_fw_application_part0_fstype" => "ext2"' examples/atomcam2_nerves_app/config/target.exs
require_grep '"a.nerves_fw_application_part0_target" => "/data"' examples/atomcam2_nerves_app/config/target.exs
require_grep 'time_file: "/data/.nerves_time"' examples/atomcam2_nerves_app/config/runtime.exs
require_grep 'system_dir: "/data/nerves_ssh"' examples/atomcam2_nerves_app/config/runtime.exs
require_grep 'user_dir: "/data/nerves_ssh/default_user"' examples/atomcam2_nerves_app/config/runtime.exs
require_grep 'if \[ -L "\$TARGET_DIR/data" \]; then' board/atomcam2/post-build.sh
require_grep 'rm "\$TARGET_DIR/data"' board/atomcam2/post-build.sh
require_grep 'mkdir -p "\$TARGET_DIR/data"' board/atomcam2/post-build.sh
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
require_grep 'runtime_mod: Atomcam2NervesApp.MOTDRuntime' examples/atomcam2_nerves_app/config/runtime.exs
require_file examples/atomcam2_nerves_app/lib/atomcam2_nerves_app/motd_runtime.ex
require_grep 'defmodule Atomcam2NervesApp.MOTDRuntime' examples/atomcam2_nerves_app/lib/atomcam2_nerves_app/motd_runtime.ex
require_grep 'def active_partition, do: "Slot A (p2)"' examples/atomcam2_nerves_app/lib/atomcam2_nerves_app/motd_runtime.ex
require_grep 'def firmware_id, do: "UUID unavailable"' examples/atomcam2_nerves_app/lib/atomcam2_nerves_app/motd_runtime.ex
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
require_grep 'mix firmware.burn' README.md
require_grep 'mix firmware.burn' examples/atomcam2_nerves_app/README.md
require_grep 'power down the camera and use mix firmware.burn' examples/atomcam2_nerves_app/lib/atomcam2_nerves_app/firmware_update.ex
reject_grep 'patch-vintage-net-linux-3.10.sh' examples/atomcam2_nerves_app/mix.exs
require_grep 'mix setup' scripts/build-firmware-log.sh
require_grep 'check_command python3' scripts/check-prereqs.sh
require_grep 'CONFIG_BLK_DEV_INITRD=y' linux-3.10.14.defconfig
require_grep 'CONFIG_INITRAMFS_SOURCE="${NERVES_DEFCONFIG_DIR}/board/atomcam2/initramfs"' linux-3.10.14.defconfig
require_grep 'CONFIG_BLK_DEV_LOOP=y' linux-3.10.14.defconfig
require_grep 'CONFIG_NLS_CODEPAGE_437=y' linux-3.10.14.defconfig
require_grep 'CONFIG_FEATURE_MOUNT_LOOP=y' busybox.fragment
require_grep 'CONFIG_PIVOT_ROOT=y' busybox.fragment
require_grep 'CONFIG_SWITCH_ROOT=y' busybox.fragment
require_grep 'CONFIG_JZMMC_V12_MMC1=y' linux-3.10.14.defconfig
require_grep 'CONFIG_JZMMC_V12_MMC1_PC_4BIT=y' linux-3.10.14.defconfig
require_grep 'CONFIG_SQUASHFS_ZLIB=y' linux-3.10.14.defconfig
require_grep 'CONFIG_CMDLINE_OVERRIDE=y' linux-3.10.14.defconfig
require_grep 'CONFIG_AWK=y' busybox.fragment
require_grep 'CONFIG_DD=y' busybox.fragment
require_grep 'CONFIG_DEVMEM=y' busybox.fragment
require_grep 'CONFIG_LN=y' busybox.fragment
require_grep 'CONFIG_RM=y' busybox.fragment
require_grep 'BR2_PACKAGE_E2FSPROGS=y' nerves_defconfig
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
require_grep 'file-resource rootfs_hack.squashfs' fwup.conf
require_grep 'host-path = ${BOOT_MANAGER}' fwup.conf
require_grep 'file-resource rootfs.img' fwup.conf
require_grep 'assert-size-lte = ${APPLICATION_PART_COUNT}' fwup.conf
require_grep 'define-eval(APPLICATION_SLOT_A_PART_OFFSET' fwup.conf
require_grep 'define-eval(APPLICATION_SLOT_B_PART_OFFSET' fwup.conf
require_grep 'define(APPLICATION_PART_COUNT, 262144)' fwup.conf
require_grep 'define-eval(DATA_PART_OFFSET' fwup.conf
require_grep 'define(DATA_PART_COUNT, 1048576)' fwup.conf
require_grep 'partition 1 {' fwup.conf
require_grep 'block-offset = .*APPLICATION_SLOT_A_PART_OFFSET' fwup.conf
require_grep 'partition 2 {' fwup.conf
require_grep 'block-offset = .*APPLICATION_SLOT_B_PART_OFFSET' fwup.conf
require_grep 'partition 3 {' fwup.conf
require_grep 'block-offset = .*DATA_PART_OFFSET' fwup.conf
require_grep 'type = 0x83 # Linux' fwup.conf
require_grep 'on-resource rootfs_hack.squashfs { fat_write' fwup.conf
require_grep 'on-resource rootfs.img { raw_write(${APPLICATION_SLOT_A_PART_OFFSET}) }' fwup.conf
reject_grep 'raw_write(${APPLICATION_SLOT_B_PART_OFFSET})' fwup.conf
require_grep 'raw_memset(${APPLICATION_SLOT_B_PART_OFFSET}, 256, 0xff)' fwup.conf
reject_grep 'raw_memset.*DATA_PART_OFFSET' fwup.conf
require_grep 'file-resource atomcam2-data-init' fwup.conf
require_grep 'contents = "format-if-missing\\n"' fwup.conf
require_grep 'on-resource atomcam2-data-init' fwup.conf
require_grep 'fat_write.*"atomcam2-data-init"' fwup.conf
require_grep 'ADR 0006 boot-manager prototype supports complete installations only' fwup.conf

fwup_upgrade_task="$(
  sed -n '/^task upgrade {/,/^}/p' "$repo_dir/fwup.conf"
)"

if [ -n "$fwup_upgrade_task" ]; then
  echo "ok: fwup.conf contains disabled upgrade task"
else
  echo "missing disabled upgrade task in fwup.conf" >&2
  exit 1
fi

if printf '%s\n' "$fwup_upgrade_task" | grep -Fq -- 'error('; then
  echo "ok: fwup upgrade task rejects prototype updates"
else
  echo "fwup upgrade task does not reject prototype updates" >&2
  exit 1
fi

for forbidden_operation in \
  fat_write \
  raw_write \
  raw_memset \
  mbr_write; do
  if printf '%s\n' "$fwup_upgrade_task" | grep -Fq -- "$forbidden_operation"; then
    echo "fwup upgrade task performs forbidden operation: $forbidden_operation" >&2
    exit 1
  else
    echo "ok: fwup upgrade task omits $forbidden_operation"
  fi
done

require_grep '.nerves' scripts/smoke-check.sh
require_grep '.nerves' scripts/atomcam2-check-minimal-ssh-scope.sh
require_grep 'tmp/log' scripts/logging.sh
require_grep 'logging.sh' scripts/build-firmware-log.sh
require_grep 'logging.sh' scripts/collect-boot-report.sh
require_grep 'atomcam2-boot-manager.env' scripts/collect-boot-report.sh
require_grep 'refusing to write SD payload to /' scripts/atomcam2-package-flat-sd.sh
require_grep 'output directory must differ from images directory' scripts/atomcam2-package-flat-sd.sh
require_grep 'kernel image is too large for the AtomCam2 boot contract' scripts/atomcam2-package-flat-sd.sh
require_grep 'ATOMCAM2_KERNEL_IMAGE must point to the verified AtomCam2 control kernel' scripts/post-image.sh
require_grep 'atomcam2-build-boot-manager.sh' scripts/post-image.sh
require_grep '"$root_dir/mnt/application"' scripts/atomcam2-build-boot-manager.sh
require_grep '"$root_dir/mnt/boot-manager"' scripts/atomcam2-build-boot-manager.sh
require_grep 'atomcam2-boot-metadata.sh' scripts/atomcam2-build-boot-manager.sh
require_grep '"$root_dir/usr/bin/atomcam2-boot-metadata"' scripts/atomcam2-build-boot-manager.sh
require_grep 'metadata_magic="ATOMCAM2_BOOT_METADATA_V1"' scripts/atomcam2-boot-metadata.sh
require_grep 'metadata_record_size=4096' scripts/atomcam2-boot-metadata.sh
require_grep 'equal_generation_conflict' scripts/atomcam2-boot-metadata.sh
require_grep 'reject malformed firmware UUID' scripts/test-atomcam2-boot-metadata.sh
require_grep 'metadata_record_a_sector=2032' scripts/atomcam2-boot-metadata.sh
require_grep 'metadata_record_b_sector=2040' scripts/atomcam2-boot-metadata.sh
require_grep 'metadata_boot_partition_sector=2048' scripts/atomcam2-boot-metadata.sh
require_grep 'metadata_select_device' scripts/atomcam2-boot-metadata.sh
require_grep 'select-device' scripts/test-atomcam2-boot-metadata.sh
require_grep 'BOOT_METADATA_RECORD_BLOCK_COUNT, 8' fwup.conf
require_grep 'BOOT_METADATA_RECORD_A_OFFSET, 2032' fwup.conf
require_grep 'BOOT_METADATA_RECORD_B_OFFSET, 2040' fwup.conf
require_grep 'metadata_write_initial_record' scripts/atomcam2-boot-metadata.sh
require_grep 'firmware-id' scripts/test-atomcam2-boot-metadata.sh
require_grep 'initial-record' scripts/test-atomcam2-boot-metadata.sh
require_grep 'metadata_choose_slot' scripts/atomcam2-boot-metadata.sh
require_grep 'metadata_choose_loaded_slot' scripts/atomcam2-boot-metadata.sh
require_grep "printf 'selected_slot=%s" scripts/atomcam2-boot-metadata.sh
require_grep 'choose pending slot from raw device' scripts/test-atomcam2-boot-metadata.sh
require_grep 'metadata_prepare_pending_image' scripts/atomcam2-boot-metadata.sh
require_grep 'metadata_write_device_copy' scripts/atomcam2-boot-metadata.sh
require_grep 'metadata_load_writable_image' scripts/atomcam2-boot-metadata.sh
require_grep 'metadata_commit_loaded_image' scripts/atomcam2-boot-metadata.sh
require_grep 'written_pending_slot_mismatch' scripts/atomcam2-boot-metadata.sh
require_grep 'written_pending_attempts_mismatch' scripts/atomcam2-boot-metadata.sh
require_grep 'image_not_regular_file' scripts/atomcam2-boot-metadata.sh
require_grep 'prepare-pending-image' scripts/test-atomcam2-boot-metadata.sh
require_grep 'preserve previously selected metadata copy' scripts/test-atomcam2-boot-metadata.sh
require_grep 'fall back after corrupt metadata mutation' scripts/test-atomcam2-boot-metadata.sh
require_grep 'reject metadata generation overflow' scripts/test-atomcam2-boot-metadata.sh
require_grep 'metadata_confirm_pending_image' scripts/atomcam2-boot-metadata.sh
require_grep 'confirm-pending-image' scripts/test-atomcam2-boot-metadata.sh
require_grep 'promote pending slot to confirmed' scripts/test-atomcam2-boot-metadata.sh
require_grep 'preserve previous metadata during confirmation' scripts/test-atomcam2-boot-metadata.sh
require_grep 'reject confirmation of non-pending slot' scripts/test-atomcam2-boot-metadata.sh
require_grep 'reject confirmation generation overflow' scripts/test-atomcam2-boot-metadata.sh
require_grep 'metadata_revert_image' scripts/atomcam2-boot-metadata.sh
require_grep 'revert-image' scripts/test-atomcam2-boot-metadata.sh
require_grep 'record previous slot as pending revert' scripts/test-atomcam2-boot-metadata.sh
require_grep 'preserve previous metadata during revert' scripts/test-atomcam2-boot-metadata.sh
require_grep 'reject revert while a slot is pending' scripts/test-atomcam2-boot-metadata.sh
require_grep 'reject revert to empty slot' scripts/test-atomcam2-boot-metadata.sh
require_grep 'reject revert to bad slot' scripts/test-atomcam2-boot-metadata.sh
require_grep 'reject revert generation overflow' scripts/test-atomcam2-boot-metadata.sh
require_grep 'metadata_prevent_revert_image' scripts/atomcam2-boot-metadata.sh
require_grep 'attempt|confirm|revert|prevent-revert' scripts/atomcam2-boot-metadata.sh
require_grep 'prevent-revert-image' scripts/test-atomcam2-boot-metadata.sh
require_grep 'mark rollback slot reusable' scripts/test-atomcam2-boot-metadata.sh
require_grep 'preserve previous metadata during prevent-revert' scripts/test-atomcam2-boot-metadata.sh
require_grep 'retain rollback eligibility after failed prevent-revert write' scripts/test-atomcam2-boot-metadata.sh
require_grep 'reject prevent-revert while a slot is pending' scripts/test-atomcam2-boot-metadata.sh
require_grep 'reject prevent-revert generation overflow' scripts/test-atomcam2-boot-metadata.sh
require_grep 'read_boot_policy' board/atomcam2/boot-manager/init
require_grep 'metadata_line#selected_slot=' board/atomcam2/boot-manager/init
require_grep 'metadata_line#selection_reason=' board/atomcam2/boot-manager/init
require_grep 'boot_policy_status=' board/atomcam2/boot-manager/init
require_grep 'boot_policy_selected_slot=' board/atomcam2/boot-manager/init
require_grep 'boot_policy_selection_reason=' board/atomcam2/boot-manager/init
require_grep 'write_report "boot_policy_selected"' board/atomcam2/boot-manager/init
require_grep 'write_report "boot_policy_unavailable"' board/atomcam2/boot-manager/init
require_grep 'choose-slot' scripts/test-atomcam2-boot-metadata.sh
require_grep 'pending_attempt_limit' scripts/test-atomcam2-boot-metadata.sh
require_grep 'initial boot metadata record' scripts/test-atomcam2-boot-metadata.sh
require_grep 'atomcam2-boot-metadata.bin' examples/atomcam2_nerves_app/scripts/preserve-final-rootfs.sh
require_grep 'initial-record' examples/atomcam2_nerves_app/scripts/preserve-final-rootfs.sh
require_grep 'define(BOOT_METADATA' fwup.conf
require_grep 'file-resource boot-metadata-a' fwup.conf
require_grep 'file-resource boot-metadata-b' fwup.conf
require_grep 'raw_write(${BOOT_METADATA_RECORD_A_OFFSET})' fwup.conf
require_grep 'raw_write(${BOOT_METADATA_RECORD_B_OFFSET})' fwup.conf
require_grep 'mkdir -p "$TARGET_DIR/mnt/boot-manager"' board/atomcam2/post-build.sh
require_grep 'atomcam2-boot-manager.squashfs' scripts/post-image.sh
require_grep 'find_boot_mount' board/atomcam2/boot-manager/init
require_grep 'ensure_boot_mount_writable' board/atomcam2/boot-manager/init
require_grep 'mount -o remount,rw' board/atomcam2/boot-manager/init
require_grep 'boot_manager_entered' board/atomcam2/boot-manager/init
require_grep 'bootstrap_kernel_filesystems' board/atomcam2/boot-manager/init
require_grep 'mount -t proc proc /proc' board/atomcam2/boot-manager/init
require_grep 'mount -t sysfs sysfs /sys' board/atomcam2/boot-manager/init
require_grep 'mount -t tmpfs tmpfs /tmp' board/atomcam2/boot-manager/init
require_grep 'slot_a_partition="${root_disk}p2"' board/atomcam2/boot-manager/init
require_grep 'slot_b_partition="${root_disk}p3"' board/atomcam2/boot-manager/init
require_grep 'data_partition="${root_disk}p4"' board/atomcam2/boot-manager/init
require_grep 'select_application_partition' board/atomcam2/boot-manager/init
require_grep 'validate_application_partition' board/atomcam2/boot-manager/init
require_grep 'application_partition="$slot_a_partition"' board/atomcam2/boot-manager/init
require_grep 'application_partition="$slot_b_partition"' board/atomcam2/boot-manager/init
require_grep 'application_partition_selected' board/atomcam2/boot-manager/init
require_grep 'application_partition_unavailable' board/atomcam2/boot-manager/init
require_grep 'application_partition_validated' board/atomcam2/boot-manager/init
require_grep 'application_partition_invalid' board/atomcam2/boot-manager/init
require_grep 'application_partition_error="partition_not_found"' board/atomcam2/boot-manager/init
require_grep 'echo "application_partition=${application_partition:-}"' board/atomcam2/boot-manager/init
require_grep 'echo "application_partition_error=${application_partition_error:-}"' board/atomcam2/boot-manager/init

require_grep 'record-pending-attempt-device' \
  board/atomcam2/boot-manager/init \
  "boot manager records pending attempts on the live device"

require_grep 'pending_boot_attempt_status=${pending_boot_attempt_status:-}' \
  board/atomcam2/boot-manager/init \
  "boot report includes pending attempt status"

require_grep 'pending_boot_attempt_error=${pending_boot_attempt_error:-}' \
  board/atomcam2/boot-manager/init \
  "boot report includes pending attempt errors"

reject_grep '^application_partition="$slot_a_partition"$' board/atomcam2/boot-manager/init
reject_grep 'find_prototype_data_partition' board/atomcam2/boot-manager/init
reject_grep 'prototype_data_partition' board/atomcam2/boot-manager/init
reject_grep 'moved_raw_stage_partition' board/atomcam2/boot-manager/init
reject_grep 'write_raw_stage' board/atomcam2/boot-manager/init
reject_grep 'conv=sync,notrunc' board/atomcam2/boot-manager/init
require_grep 'metadata_command="/usr/bin/atomcam2-boot-metadata"' board/atomcam2/boot-manager/init
require_grep 'read_boot_metadata' board/atomcam2/boot-manager/init
require_grep 'select-device' board/atomcam2/boot-manager/init
require_grep 'boot_metadata_status="unavailable"' board/atomcam2/boot-manager/init
require_grep 'boot_metadata_status="selected"' board/atomcam2/boot-manager/init
require_grep 'boot_metadata_selected_copy=' board/atomcam2/boot-manager/init
require_grep 'boot_metadata_generation=' board/atomcam2/boot-manager/init
require_grep 'boot_metadata_confirmed_slot=' board/atomcam2/boot-manager/init
require_grep 'write_report "boot_metadata_selected"' board/atomcam2/boot-manager/init
require_grep 'write_report "boot_metadata_unavailable"' board/atomcam2/boot-manager/init
require_grep 'mount -t squashfs -o ro' board/atomcam2/boot-manager/init
require_grep 'pivot_root_command="/sbin/pivot_root"' board/atomcam2/boot-manager/init
require_grep '"\$pivot_root_command" \. "\$old_root_relative_mount"' board/atomcam2/boot-manager/init
require_grep 'exec /sbin/init' board/atomcam2/boot-manager/init
require_grep 'exec 9>/dev/null' board/atomcam2/boot-manager/init
require_grep '2>&9' board/atomcam2/boot-manager/init
require_grep 'exec 9>&-' board/atomcam2/boot-manager/init
require_grep 'temporary_output_path=' board/atomcam2/boot-manager/init
require_grep 'dev_move' board/atomcam2/boot-manager/init
require_grep 'dev_moved' board/atomcam2/boot-manager/init
require_grep 'sys_move' board/atomcam2/boot-manager/init
require_grep 'boot_mount_move' board/atomcam2/boot-manager/init
require_grep 'proc_move' board/atomcam2/boot-manager/init
require_grep 'proc_moved' board/atomcam2/boot-manager/init
require_grep 'pivot_root_error_path=' board/atomcam2/boot-manager/init
require_grep 'old_root_mount="/mnt/boot-manager"' board/atomcam2/boot-manager/init
require_grep 'old_root_relative_mount="mnt/boot-manager"' board/atomcam2/boot-manager/init
require_grep 'application_umount_command=' board/atomcam2/boot-manager/init
require_grep '"\$application_umount_command"' board/atomcam2/boot-manager/init
require_grep 'old_root_unmount_error_path=' board/atomcam2/boot-manager/init
require_grep '"\$old_root_mount"' board/atomcam2/boot-manager/init
require_grep 'write_report "pivot_root_returned"' board/atomcam2/boot-manager/init
require_grep 'pivot_root_failed_${pivot_root_status}' board/atomcam2/boot-manager/init
require_grep 'write_report "old_root_unmount"' board/atomcam2/boot-manager/init
require_grep 'write_report "old_root_unmounted"' board/atomcam2/boot-manager/init
require_grep 'b50658eac32b57fdcb20383d82a54e6439acd7a3f7e9cb8b43edf4a4b89b03bc' scripts/post-image.sh
require_grep 'ATOMCAM2_KERNEL_IMAGE' scripts/release-artifacts.sh
require_grep 'unexpected AtomCam2 control kernel SHA256' scripts/release-artifacts.sh
require_grep 'toolchain/VERSION' scripts/release-artifacts.sh
require_grep 'checksum_paths' scripts/release-artifacts.sh
require_grep '\-\-kernel-image' scripts/atomcam2-package-flat-sd.sh
require_grep '\-\-rootfs-image' scripts/atomcam2-package-flat-sd.sh
require_grep 'post_processing_script' examples/atomcam2_nerves_app/config/target.exs
require_grep 'rootfs_hack.final.squashfs' examples/atomcam2_nerves_app/scripts/preserve-final-rootfs.sh
require_grep 'cannot resolve images directory' scripts/atomcam2-package-flat-sd.sh
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

require_grep 'find_boot_partition' rootfs_overlay/usr/bin/atomcam2-pre-run
require_grep 'create_rootdisk_links' rootfs_overlay/usr/bin/atomcam2-pre-run
require_grep '/dev/rootdisk0p1' rootfs_overlay/usr/bin/atomcam2-pre-run
require_grep '/dev/rootdisk0p2' rootfs_overlay/usr/bin/atomcam2-pre-run
require_grep '/dev/rootdisk0p3' rootfs_overlay/usr/bin/atomcam2-pre-run
require_grep '/dev/rootdisk0p4' rootfs_overlay/usr/bin/atomcam2-pre-run
require_grep 'application_slot_a_partition="${root_disk}p2"' rootfs_overlay/usr/bin/atomcam2-pre-run
require_grep 'application_slot_b_partition="${root_disk}p3"' rootfs_overlay/usr/bin/atomcam2-pre-run
require_grep 'application_partition="$application_slot_a_partition"' rootfs_overlay/usr/bin/atomcam2-pre-run
require_grep 'data_partition="${root_disk}p4"' rootfs_overlay/usr/bin/atomcam2-pre-run
require_grep 'data_init_marker=' rootfs_overlay/usr/bin/atomcam2-pre-run
require_grep 'data_initialization_requested' rootfs_overlay/usr/bin/atomcam2-pre-run
require_grep 'format-if-missing' rootfs_overlay/usr/bin/atomcam2-pre-run
require_grep '/sbin/dumpe2fs -h' rootfs_overlay/usr/bin/atomcam2-pre-run
require_grep '/sbin/mkfs.ext2' rootfs_overlay/usr/bin/atomcam2-pre-run
require_grep '/bin/mount' rootfs_overlay/usr/bin/atomcam2-pre-run
require_grep '.atomcam2-write-probe' rootfs_overlay/usr/bin/atomcam2-pre-run
require_grep 'rm -f "$data_init_marker"' rootfs_overlay/usr/bin/atomcam2-pre-run
require_grep 'write_report "pre_run_failed"' rootfs_overlay/usr/bin/atomcam2-pre-run
require_grep 'write_report "pre_run_complete"' rootfs_overlay/usr/bin/atomcam2-pre-run
reject_grep 'create_rootdisk_links' board/atomcam2/initramfs/init

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
  \( -name '*.sh' -o -path '*/usr/bin/atomcam2-*' -o -path '*/initramfs/init' -o -path '*/boot-manager/init' \) \
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
require_grep 'await_initialization_timeout: 5_000' examples/atomcam2_nerves_app/config/runtime.exs

require_file examples/atomcam2_nerves_app/lib/atomcam2_nerves_app/time_sync.ex
require_grep 'Atomcam2NervesApp.TimeSync' examples/atomcam2_nerves_app/lib/atomcam2_nerves_app/application.ex
require_grep 'VintageNet.subscribe(@connection_property)' examples/atomcam2_nerves_app/lib/atomcam2_nerves_app/time_sync.ex
require_grep 'NervesTime.restart_ntpd()' examples/atomcam2_nerves_app/lib/atomcam2_nerves_app/time_sync.ex

# Verify the boot metadata codec behavior.
metadata_test="$(
  CDPATH= cd -- "$(dirname "$0")" &&
    pwd
)/test-atomcam2-boot-metadata.sh"

if [ ! -x "$metadata_test" ]; then
  echo "error: metadata test is not executable: $metadata_test" >&2
  exit 1
fi

"$metadata_test"
