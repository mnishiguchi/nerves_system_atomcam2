#!/bin/sh
set -eu

images_dir="target/images"
output_dir="target/atomcam2-sd"
hostname_value="nerves"
authorized_keys_file=""

usage() {
  cat <<'USAGE'
Usage: scripts/atomcam2-package-flat-sd.sh [options]

Options:
  --images-dir DIR          Directory containing uImage.lzma and rootfs.squashfs
  --output-dir DIR          Output directory for AtomCam2 SD files
  --hostname NAME           Hostname written to SD-card hostname file
  --authorized-keys FILE    Public key file copied to authorized_keys
  -h, --help                Show this help
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --images-dir) images_dir="$2"; shift 2 ;;
    --output-dir) output_dir="$2"; shift 2 ;;
    --hostname) hostname_value="$2"; shift 2 ;;
    --authorized-keys) authorized_keys_file="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

kernel_image="$images_dir/uImage.lzma"
rootfs_image="$images_dir/rootfs.squashfs"

if [ ! -f "$kernel_image" ]; then
  echo "missing kernel image: $kernel_image" >&2
  exit 1
fi

if [ ! -f "$rootfs_image" ]; then
  echo "missing rootfs image: $rootfs_image" >&2
  exit 1
fi

rm -rf "$output_dir"
mkdir -p "$output_dir"

cp "$kernel_image" "$output_dir/factory_t31_ZMC6tiIDQN"
cp "$rootfs_image" "$output_dir/rootfs_hack.squashfs"
printf '%s\n' "$hostname_value" > "$output_dir/hostname"

if [ -n "$authorized_keys_file" ]; then
  if [ ! -f "$authorized_keys_file" ]; then
    echo "missing authorized keys file: $authorized_keys_file" >&2
    exit 1
  fi
  cp "$authorized_keys_file" "$output_dir/authorized_keys"
else
  : > "$output_dir/authorized_keys"
fi

cat > "$output_dir/nerves-provisioning.conf" <<EOF_PROVISIONING
NERVES_WIFI_SSID=${NERVES_WIFI_SSID:-}
NERVES_WIFI_PASSPHRASE=${NERVES_WIFI_PASSPHRASE:-}
EOF_PROVISIONING

cat <<MESSAGE
AtomCam2 SD payload created:
$output_dir

Required files:
- factory_t31_ZMC6tiIDQN
- rootfs_hack.squashfs
- hostname
- authorized_keys
- nerves-provisioning.conf
MESSAGE
