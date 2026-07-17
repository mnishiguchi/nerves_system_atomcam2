#!/bin/sh
set -eu

payload_dir="${1:-target/atomcam2-sd}"
failures=0

usage() {
  cat <<'USAGE'
Usage: scripts/atomcam2-check-sd-payload.sh [PAYLOAD_DIR]

Default PAYLOAD_DIR: target/atomcam2-sd
USAGE
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

require_file() {
  file_name="$1"
  empty_policy="${2:-}"
  file_path="$payload_dir/$file_name"

  if [ -s "$file_path" ] || { [ -f "$file_path" ] && [ "$empty_policy" = "allow_empty" ]; }; then
    echo "ok: $file_path"
  else
    echo "missing or empty: $file_path" >&2
    failures=$((failures + 1))
  fi
}

check_hostname() {
  hostname_value="$(sed -n '1p' "$payload_dir/hostname" 2>/dev/null || true)"

  case "$hostname_value" in
    ""|.*|-*|*-|*..*|*.-*|*-.*|*[!A-Za-z0-9.-]*)
      echo "invalid hostname: $hostname_value" >&2
      failures=$((failures + 1))
      return 0
      ;;
  esac

  if [ "$hostname_value" = "nerves" ]; then
    echo "ok: hostname keeps nerves.local stable"
  else
    echo "warning: hostname is '$hostname_value', not 'nerves'"
  fi
}

if [ ! -d "$payload_dir" ]; then
  echo "missing payload directory: $payload_dir" >&2
  exit 1
fi

require_file factory_t31_ZMC6tiIDQN required
require_file rootfs_hack.squashfs required
require_file hostname required
require_file authorized_keys allow_empty
require_file nerves-provisioning.conf allow_empty

firmware_metadata_file="$payload_dir/nerves-firmware-metadata.conf"

if [ -e "$firmware_metadata_file" ]; then
  require_file nerves-firmware-metadata.conf

  for metadata_key in     nerves_fw_active     a.nerves_fw_product     a.nerves_fw_version     a.nerves_fw_uuid     a.nerves_fw_platform     a.nerves_fw_architecture
  do
    metadata_value="$(
      awk -F= -v wanted="$metadata_key" '
        $1 == wanted {
          print substr($0, index($0, "=") + 1)
          exit
        }
      ' "$firmware_metadata_file"
    )"

    if [ -n "$metadata_value" ]; then
      echo "ok: $firmware_metadata_file contains $metadata_key"
    else
      echo "invalid firmware metadata: missing $metadata_key" >&2
      exit 1
    fi
  done
fi

check_hostname

if [ "$failures" -gt 0 ]; then
  exit 1
fi
