#!/bin/sh
set -eu

images_dir="${BINARIES_DIR:-}"
if [ -z "$images_dir" ]; then
  echo "BINARIES_DIR is not set" >&2
  exit 1
fi

output_dir="$images_dir/atomcam2-sd"

if [ -n "${ATOMCAM2_AUTHORIZED_KEYS:-}" ]; then
  "${NERVES_DEFCONFIG_DIR}/scripts/atomcam2-package-flat-sd.sh" \
    --images-dir "$images_dir" \
    --output-dir "$output_dir" \
    --hostname "${ATOMCAM2_HOSTNAME:-nerves}" \
    --authorized-keys "$ATOMCAM2_AUTHORIZED_KEYS"
else
  "${NERVES_DEFCONFIG_DIR}/scripts/atomcam2-package-flat-sd.sh" \
    --images-dir "$images_dir" \
    --output-dir "$output_dir" \
    --hostname "${ATOMCAM2_HOSTNAME:-nerves}"
fi

echo "AtomCam2 SD payload written to $output_dir"
