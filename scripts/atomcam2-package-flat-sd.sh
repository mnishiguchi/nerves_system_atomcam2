#!/bin/sh
set -eu

images_dir="target/images"
output_dir="target/atomcam2-sd"
hostname_value="nerves"
authorized_keys_file=""
kernel_image=""
rootfs_image=""

usage() {
  cat <<'USAGE'
Usage: scripts/atomcam2-package-flat-sd.sh [options]

Options:
  --images-dir DIR          Directory containing uImage.lzma and rootfs.squashfs
  --output-dir DIR          Output directory for AtomCam2 SD files
  --hostname NAME           Hostname written to SD-card hostname file
  --authorized-keys FILE    Public key file copied to authorized_keys
  --kernel-image FILE       Kernel override for a hybrid control boot
  --rootfs-image FILE       Final application SquashFS override
  -h, --help                Show this help
USAGE
}

fail() {
  echo "error: $*" >&2
  exit 1
}

require_option_value() {
  option_name="$1"
  option_value="${2:-}"

  [ -n "$option_value" ] || fail "$option_name requires a value"
}

validate_hostname() {
  case "$hostname_value" in
    ""|.*|-*|*-|*..*|*.-*|*-.*|*[!A-Za-z0-9.-]*)
      fail "invalid hostname: $hostname_value"
      ;;
  esac
}

physical_dir() {
  (CDPATH= cd -- "$1" 2>/dev/null && pwd -P)
}

validate_output_dir() {
  [ -n "$output_dir" ] || fail "output directory is empty"
  [ "$output_dir" != "/" ] || fail "refusing to write SD payload to /"
  [ "$output_dir" != "." ] || fail "refusing to replace current directory"

  output_basename="${output_dir##*/}"
  case "$output_basename" in
    .|..) fail "refusing unsafe output directory: $output_dir" ;;
  esac

  [ -d "$images_dir" ] || fail "missing images directory: $images_dir"

  case "$output_dir" in
    */*)
      output_parent="${output_dir%/*}"
      [ -n "$output_parent" ] || output_parent="/"
      ;;
    *)
      output_parent="."
      ;;
  esac

  mkdir -p "$output_parent"

  images_dir_real="$(physical_dir "$images_dir")" || fail "cannot resolve images directory: $images_dir"
  output_parent_real="$(physical_dir "$output_parent")" || fail "cannot resolve output parent: $output_parent"
  output_dir_real="$output_parent_real/$output_basename"

  [ "$output_dir_real" != "$images_dir_real" ] || fail "output directory must differ from images directory"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --images-dir)
      require_option_value "$1" "${2:-}"
      images_dir="$2"
      shift 2
      ;;
    --output-dir)
      require_option_value "$1" "${2:-}"
      output_dir="$2"
      shift 2
      ;;
    --hostname)
      require_option_value "$1" "${2:-}"
      hostname_value="$2"
      shift 2
      ;;
    --authorized-keys)
      require_option_value "$1" "${2:-}"
      authorized_keys_file="$2"
      shift 2
      ;;
    --kernel-image)
      require_option_value "$1" "${2:-}"
      kernel_image="$2"
      shift 2
      ;;
    --rootfs-image)
      require_option_value "$1" "${2:-}"
      rootfs_image="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

images_dir="${images_dir%/}"
output_dir="${output_dir%/}"

validate_hostname
validate_output_dir

if [ -z "$kernel_image" ]; then
  kernel_image="$images_dir/uImage.lzma"
fi

if [ -z "$rootfs_image" ]; then
  rootfs_image="$images_dir/rootfs.squashfs"
fi

[ -f "$kernel_image" ] || fail "missing kernel image: $kernel_image"
[ -f "$rootfs_image" ] || fail "missing rootfs image: $rootfs_image"

max_kernel_size=$((1984 * 1024))
kernel_size=$(wc -c < "$kernel_image")

if [ "$kernel_size" -gt "$max_kernel_size" ]; then
  fail "kernel image is too large for the AtomCam2 boot contract: ${kernel_size} bytes (maximum ${max_kernel_size})"
fi

if [ -n "$authorized_keys_file" ]; then
  [ -f "$authorized_keys_file" ] || fail "missing authorized keys file: $authorized_keys_file"
fi

rm -rf "$output_dir"
mkdir -p "$output_dir"

cp "$kernel_image" "$output_dir/factory_t31_ZMC6tiIDQN"
cp "$rootfs_image" "$output_dir/rootfs_hack.squashfs"
printf '%s\n' "$hostname_value" > "$output_dir/hostname"

if [ -n "$authorized_keys_file" ]; then
  cp "$authorized_keys_file" "$output_dir/authorized_keys"
else
  : > "$output_dir/authorized_keys"
fi

if [ -f "$images_dir/nerves-provisioning.conf" ]; then
  cp "$images_dir/nerves-provisioning.conf" "$output_dir/nerves-provisioning.conf"
else
  cat > "$output_dir/nerves-provisioning.conf" <<EOF_PROVISIONING
NERVES_WIFI_SSID=${NERVES_WIFI_SSID:-}
NERVES_WIFI_PASSPHRASE=${NERVES_WIFI_PASSPHRASE:-}
EOF_PROVISIONING
fi

cat <<MESSAGE
AtomCam2 SD payload created:
$output_dir

Kernel source:
$kernel_image

Rootfs source:
$rootfs_image

Required files:
- factory_t31_ZMC6tiIDQN
- rootfs_hack.squashfs
- hostname
- authorized_keys
- nerves-provisioning.conf
MESSAGE
