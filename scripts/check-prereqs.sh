#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
toolchain_archive="$repo_root/target/toolchains/atomcam2-mips32r2-nerves-toolchain.tar.xz"

missing=0

check_command() {
  local command_name="$1"

  if command -v "$command_name" >/dev/null 2>&1; then
    echo "ok: $command_name"
  else
    echo "missing: $command_name"
    missing=1
  fi
}

check_optional_command() {
  local command_name="$1"
  local note="$2"

  if command -v "$command_name" >/dev/null 2>&1; then
    echo "ok: $command_name"
  else
    echo "optional: $command_name ($note)"
  fi
}

check_command bash
check_command git
check_command make
check_command gcc
check_command g++
check_command erl
check_command elixir
check_command mix
check_command cpio
check_command fwup
check_command unsquashfs

# Buildroot can build host mksquashfs for BR2_TARGET_ROOTFS_SQUASHFS, so do not
# fail early just because the host package is missing.
check_optional_command mksquashfs "Buildroot can build host squashfs-tools"

if [ -s "$toolchain_archive" ]; then
  echo "ok: $toolchain_archive"
else
  echo "missing: $toolchain_archive"
  echo "Run ./scripts/prepare-toolchain-archive.sh"
  missing=1
fi

if [ "$missing" -ne 0 ]; then
  echo "Install missing required commands before building."
  exit 1
fi

echo "Prerequisites look usable for the first experiment."
