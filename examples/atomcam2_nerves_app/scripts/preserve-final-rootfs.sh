#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <combined.squashfs>" >&2
  exit 1
fi

source_rootfs="$1"
build_path="${MIX_BUILD_PATH:-}"
system_path="${NERVES_SYSTEM:-}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

if [ ! -f "$source_rootfs" ]; then
  echo "source rootfs does not exist: $source_rootfs" >&2
  exit 1
fi

if [ -z "$build_path" ]; then
  echo "MIX_BUILD_PATH is not set" >&2
  exit 1
fi

if [ -z "$system_path" ] || [ ! -d "$system_path/images" ]; then
  echo "NERVES_SYSTEM images directory is unavailable: $system_path/images" >&2
  exit 1
fi

output_dir="$build_path/nerves/images"
preserved_rootfs="$output_dir/rootfs_hack.final.squashfs"
summary_path="$preserved_rootfs.summary.txt"
payload_dir="$output_dir/atomcam2-sd"
listing_file="$(mktemp)"

cleanup() {
  rm -f "$listing_file"
}
trap cleanup EXIT

mkdir -p "$output_dir"
cp --remove-destination -- "$source_rootfs" "$preserved_rootfs"

unsquashfs -ll "$preserved_rootfs" srv/erlang > "$listing_file"

if ! grep -q 'squashfs-root/srv/erlang' "$listing_file"; then
  echo "preserved rootfs does not contain /srv/erlang" >&2
  exit 1
fi

hostname_value="nerves"
if [ -s "$system_path/images/hostname" ]; then
  IFS= read -r hostname_value < "$system_path/images/hostname"
fi

package_args=(
  --images-dir "$system_path/images"
  --rootfs-image "$preserved_rootfs"
  --output-dir "$payload_dir"
  --hostname "$hostname_value"
)

if [ -f "$system_path/images/authorized_keys" ]; then
  package_args+=(
    --authorized-keys "$system_path/images/authorized_keys"
  )
fi

"$repo_root/scripts/atomcam2-package-flat-sd.sh" "${package_args[@]}"

final_size_bytes="$(wc -c < "$preserved_rootfs" | tr -d '[:space:]')"
base_rootfs="$system_path/images/rootfs.squashfs"

{
  echo "preserved_rootfs=$preserved_rootfs"
  echo "preserved_rootfs_size_bytes=$final_size_bytes"
  echo "preserved_rootfs_sha256=$(sha256sum "$preserved_rootfs" | awk '{print $1}')"

  if [ -f "$base_rootfs" ]; then
    echo "base_rootfs=$base_rootfs"
    echo "base_rootfs_size_bytes=$(wc -c < "$base_rootfs" | tr -d '[:space:]')"
  fi

  echo "srv_erlang_present=yes"
  echo "sd_payload=$payload_dir"
} > "$summary_path"

echo "Preserved merged rootfs: $preserved_rootfs"
echo "Rootfs inspection summary: $summary_path"
echo "Final AtomCam2 SD payload: $payload_dir"
