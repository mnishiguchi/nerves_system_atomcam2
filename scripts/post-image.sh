#!/bin/sh
set -eu

fail() {
  echo "error: $*" >&2
  exit 1
}

images_dir="${BINARIES_DIR:-}"
[ -n "$images_dir" ] || fail "BINARIES_DIR is not set"
[ -d "$images_dir" ] || fail "BINARIES_DIR does not exist: $images_dir"
[ -n "${NERVES_DEFCONFIG_DIR:-}" ] || fail "NERVES_DEFCONFIG_DIR is not set"
[ -d "$NERVES_DEFCONFIG_DIR" ] || fail "NERVES_DEFCONFIG_DIR does not exist: $NERVES_DEFCONFIG_DIR"
[ -n "${BR2_EXTERNAL_NERVES_PATH:-}" ] || fail "BR2_EXTERNAL_NERVES_PATH is not set"
[ -d "$BR2_EXTERNAL_NERVES_PATH" ] || fail "BR2_EXTERNAL_NERVES_PATH does not exist: $BR2_EXTERNAL_NERVES_PATH"

hostname_value="${ATOMCAM2_HOSTNAME:-nerves}"
authorized_keys_image="$images_dir/authorized_keys"
hostname_image="$images_dir/hostname"
provisioning_image="$images_dir/nerves-provisioning.conf"
output_dir="$images_dir/atomcam2-sd"
artifact_dir=$(CDPATH= cd -- "$images_dir/.." && pwd)
artifact_scripts_dir="$artifact_dir/scripts"

mkdir -p "$artifact_scripts_dir"
for script_name in merge-squashfs rel2fw.sh scrub-otp-release.sh; do
  install -m 0755 \
    "$BR2_EXTERNAL_NERVES_PATH/scripts/$script_name" \
    "$artifact_scripts_dir/$script_name"
done

printf '%s\n' "$hostname_value" > "$hostname_image"

if [ -n "${ATOMCAM2_AUTHORIZED_KEYS:-}" ]; then
  [ -f "$ATOMCAM2_AUTHORIZED_KEYS" ] || fail "ATOMCAM2_AUTHORIZED_KEYS does not exist: $ATOMCAM2_AUTHORIZED_KEYS"
  cp "$ATOMCAM2_AUTHORIZED_KEYS" "$authorized_keys_image"
else
  : > "$authorized_keys_image"
fi

cat > "$provisioning_image" <<EOF_PROVISIONING
NERVES_WIFI_SSID=${NERVES_WIFI_SSID:-}
NERVES_WIFI_PASSPHRASE=${NERVES_WIFI_PASSPHRASE:-}
EOF_PROVISIONING

if [ -n "${ATOMCAM2_KERNEL_IMAGE:-}" ]; then
  [ -f "$ATOMCAM2_KERNEL_IMAGE" ] || fail "ATOMCAM2_KERNEL_IMAGE does not exist: $ATOMCAM2_KERNEL_IMAGE"

  cp "$ATOMCAM2_KERNEL_IMAGE" "$images_dir/uImage.lzma"
  echo "Using AtomCam2 kernel override: $ATOMCAM2_KERNEL_IMAGE"
fi

"${NERVES_DEFCONFIG_DIR}/scripts/atomcam2-package-flat-sd.sh" \
  --images-dir "$images_dir" \
  --output-dir "$output_dir" \
  --hostname "$hostname_value" \
  --authorized-keys "$authorized_keys_image"

echo "AtomCam2 SD payload written to $output_dir"
