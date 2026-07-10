#!/bin/sh
set -eu

payload_dir="${1:-target/atomcam2-sd}"

failures=0

require_file() {
  file_path="$payload_dir/$1"
  if [ -s "$file_path" ] || [ "$2" = "allow_empty" ]; then
    echo "ok: $file_path"
  else
    echo "missing or empty: $file_path" >&2
    failures=$((failures + 1))
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

hostname_value="$(sed -n '1p' "$payload_dir/hostname" 2>/dev/null || true)"
if [ "$hostname_value" = "nerves" ]; then
  echo "ok: hostname keeps nerves.local stable"
else
  echo "warning: hostname is '$hostname_value', not 'nerves'"
fi

if [ "$failures" -gt 0 ]; then
  exit 1
fi
