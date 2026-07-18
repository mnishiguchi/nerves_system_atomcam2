#!/bin/sh
set -eu

fail() {
  echo "error: $*" >&2
  exit 1
}

require_command() {
  command_name="$1"

  if command -v "$command_name" >/dev/null 2>&1; then
    return 0
  else
    fail "required command is unavailable: $command_name"
  fi
}

require_compiler_setting() {
  pattern="$1"
  description="$2"

  if printf '%s\n' "$compiler_settings" | grep -Eq -- "$pattern"; then
    echo "ok: $description"
  else
    fail "compiler setting mismatch: $description"
  fi
}

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
repo_root="$(CDPATH= cd -- "$script_dir/.." && pwd)"

toolchain_root="${NERVES_TOOLCHAIN:-}"
toolchain_archive="$repo_root/target/toolchains/atomcam2-mips32r2-nerves-toolchain.tar.xz"
toolchain_compiler="$toolchain_root/bin/mipsel-nerves-linux-musl-gcc"

if [ "${1:-}" = "--force" ]; then
  force=true
elif [ -n "${1:-}" ]; then
  fail "usage: $0 [--force]"
else
  force=false
fi

if [ -z "$toolchain_root" ]; then
  fail "NERVES_TOOLCHAIN must point to the validated Atom Cam 2 compiler directory"
elif [ ! -d "$toolchain_root" ]; then
  fail "toolchain directory is missing: $toolchain_root"
elif [ ! -x "$toolchain_compiler" ]; then
  fail "toolchain compiler is unavailable: $toolchain_compiler"
fi

require_command grep
require_command mktemp
require_command tar

compiler_target="$("$toolchain_compiler" -dumpmachine)"

if [ "$compiler_target" = "mipsel-nerves-linux-musl" ]; then
  echo "ok: compiler target is $compiler_target"
else
  fail "unexpected compiler target: $compiler_target"
fi

validation_object="$(mktemp)"

cleanup_validation() {
  rm -f "$validation_object"
}

trap cleanup_validation EXIT HUP INT TERM

compiler_settings="$(
  "$toolchain_compiler" \
    -Q \
    --help=target \
    -c \
    -x c \
    /dev/null \
    -o "$validation_object" 2>&1
)"

rm -f "$validation_object"
trap - EXIT HUP INT TERM

require_compiler_setting \
  '-mabi=ABI[[:space:]]+32([[:space:]]|$)' \
  "MIPS o32 ABI"

require_compiler_setting \
  '-march=ISA[[:space:]]+mips32r2([[:space:]]|$)' \
  "MIPS32 Release 2 architecture"

require_compiler_setting \
  '-msoft-float[[:space:]]+\[enabled\]' \
  "software floating point enabled"

require_compiler_setting \
  '-mhard-float[[:space:]]+\[disabled\]' \
  "hardware floating point disabled"

require_compiler_setting \
  '-mdsp[[:space:]]+\[disabled\]' \
  "DSP ASE disabled"

require_compiler_setting \
  '-mdspr2[[:space:]]+\[disabled\]' \
  "DSP R2 ASE disabled"

if [ -s "$toolchain_archive" ] && [ "$force" = false ]; then
  echo "ok: toolchain archive already exists"
  echo "$toolchain_archive"
  exit 0
fi

toolchain_parent="$(dirname "$toolchain_root")"
toolchain_directory="$(basename "$toolchain_root")"
archive_directory="$(dirname "$toolchain_archive")"
temporary_archive="$toolchain_archive.tmp"

mkdir -p "$archive_directory"
rm -f "$temporary_archive"

cleanup() {
  rm -f "$temporary_archive"
}

trap cleanup EXIT HUP INT TERM

echo "Preparing AtomCam2 toolchain archive"
echo "  source: $toolchain_root"
echo "  output: $toolchain_archive"

tar \
  -C "$toolchain_parent" \
  -cJf "$temporary_archive" \
  "$toolchain_directory"

if [ ! -s "$temporary_archive" ]; then
  fail "generated archive is missing or empty"
elif ! tar -tJf "$temporary_archive" >/dev/null; then
  fail "generated archive cannot be read"
fi

archive_root="$(
  tar -tJf "$temporary_archive" |
    sed -n '1p'
)"
expected_archive_root="$toolchain_directory/"

if [ "$archive_root" != "$expected_archive_root" ]; then
  fail "unexpected archive root: $archive_root"
fi

mv "$temporary_archive" "$toolchain_archive"
trap - EXIT HUP INT TERM

echo "ok: toolchain archive created"
ls -lh "$toolchain_archive"
