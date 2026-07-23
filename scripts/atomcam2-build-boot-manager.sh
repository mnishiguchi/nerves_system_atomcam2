#!/bin/sh
set -eu

fail() {
  echo "error: $*" >&2
  exit 1
}

find_tool() {
  tool_name="$1"

  if [ -n "${HOST_DIR:-}" ] && [ -x "$HOST_DIR/bin/$tool_name" ]; then
    printf '%s\n' "$HOST_DIR/bin/$tool_name"
  elif command -v "$tool_name" >/dev/null 2>&1; then
    command -v "$tool_name"
  else
    return 1
  fi
}

if [ "$#" -ne 3 ]; then
  echo "usage: $0 <source-rootfs> <output-image> <init-script>" >&2
  exit 1
fi

source_rootfs="$1"
output_image="$2"
init_script="$3"

if [ ! -f "$source_rootfs" ]; then
  fail "source rootfs does not exist: $source_rootfs"
fi

if [ "$source_rootfs" = "$output_image" ]; then
  fail "output image must differ from the source rootfs"
fi

if [ ! -x "$init_script" ]; then
  fail "boot-manager init is not executable: $init_script"
fi

if unsquashfs_command="$(find_tool unsquashfs)"; then
  :
else
  fail "unsquashfs is unavailable"
fi

if mksquashfs_command="$(find_tool mksquashfs)"; then
  :
else
  fail "mksquashfs is unavailable"
fi

output_parent="${output_image%/*}"
if [ "$output_parent" = "$output_image" ]; then
  output_parent="."
fi
mkdir -p "$output_parent"

temporary_dir="$(mktemp -d)"
root_dir="$temporary_dir/root"
extracted_init="$temporary_dir/init"
listing_file="$temporary_dir/listing.txt"

cleanup() {
  rm -rf "$temporary_dir"
}
trap cleanup EXIT

"$unsquashfs_command" -d "$root_dir" "$source_rootfs" >/dev/null

if [ ! -x "$root_dir/sbin/pivot_root" ]; then
  fail "source rootfs does not provide /sbin/pivot_root"
fi

if [ ! -x "$root_dir/bin/umount" ] && [ ! -x "$root_dir/sbin/umount" ]; then
  fail "source rootfs does not provide umount"
fi

rm -f "$root_dir/sbin/init" "$root_dir/sbin/init.real"
rm -rf "$root_dir/srv/erlang"

mkdir -p \
  "$root_dir/dev" \
  "$root_dir/proc" \
  "$root_dir/sys" \
  "$root_dir/tmp" \
  "$root_dir/boot" \
  "$root_dir/media/mmc" \
  "$root_dir/mnt/application" \
  "$root_dir/mnt/boot-manager"

install -m 0755 "$init_script" "$root_dir/sbin/init"

rm -f "$output_image"
"$mksquashfs_command" \
  "$root_dir" \
  "$output_image" \
  -noappend \
  -comp gzip \
  -all-root \
  >/dev/null

"$unsquashfs_command" -cat "$output_image" sbin/init > "$extracted_init"
if ! cmp -s "$init_script" "$extracted_init"; then
  fail "boot-manager image contains an unexpected /sbin/init"
fi

"$unsquashfs_command" -ll "$output_image" > "$listing_file"
if grep -q 'squashfs-root/srv/erlang' "$listing_file"; then
  fail "boot-manager image unexpectedly contains an Erlang release"
fi

echo "Boot-manager prototype image: $output_image"
echo "SHA-256: $(sha256sum "$output_image" | awk '{print $1}')"
