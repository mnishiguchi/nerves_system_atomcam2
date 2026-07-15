#!/bin/sh
set -eu

fail() {
  echo "error: $*" >&2
  exit 1
}

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
repo_root="$(CDPATH= cd -- "$script_dir/.." && pwd)"

default_toolchain_root="$HOME/Projects/nerves/toolchains/o/nerves_toolchain_mipsel_nerves_linux_musl/x-tools/mipsel-nerves-linux-musl"
toolchain_root="${NERVES_TOOLCHAIN:-$default_toolchain_root}"
toolchain_archive="$repo_root/target/toolchains/atomcam2-mips32r2-nerves-toolchain.tar.xz"
toolchain_compiler="$toolchain_root/bin/mipsel-nerves-linux-musl-gcc"

if [ "${1:-}" = "--force" ]; then
  force=true
elif [ -n "${1:-}" ]; then
  fail "usage: $0 [--force]"
else
  force=false
fi

if [ -s "$toolchain_archive" ] && [ "$force" = false ]; then
  echo "ok: toolchain archive already exists"
  echo "$toolchain_archive"
  exit 0
fi

if [ ! -d "$toolchain_root" ]; then
  fail "toolchain directory is missing: $toolchain_root"
elif [ ! -x "$toolchain_compiler" ]; then
  fail "toolchain compiler is unavailable: $toolchain_compiler"
fi

if ! command -v tar >/dev/null 2>&1; then
  fail "required command is unavailable: tar"
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
