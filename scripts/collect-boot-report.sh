#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mount_dir=""
output_root="target/atomcam2-boot-reports"

usage() {
  cat <<'USAGE'
Usage: scripts/collect-boot-report.sh --mount MOUNT_DIR [options]

Collect first-boot breadcrumbs from a mounted AtomCam2 SD-card FAT partition.

Options:
  --mount DIR      Mounted AtomCam2 SD-card FAT partition
  --output DIR     Output root directory. Default: target/atomcam2-boot-reports
  -h, --help       Show this help
USAGE
}

fail() {
  echo "error: $*" >&2
  exit 1
}

require_option_value() {
  local option_name="$1"
  local option_value="${2:-}"

  if [ -z "$option_value" ]; then
    fail "$option_name requires a value"
  fi
}

physical_dir() {
  (cd "$1" 2>/dev/null && pwd -P)
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --mount)
      require_option_value "$1" "${2:-}"
      mount_dir="$2"
      shift 2
      ;;
    --output)
      require_option_value "$1" "${2:-}"
      output_root="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

copy_if_present() {
  local path="$1"
  local destination_dir="$2"

  if [ -e "$mount_dir/$path" ]; then
    cp -a "$mount_dir/$path" "$destination_dir/$path"
    echo "copied: $path"
  else
    echo "missing: $path"
  fi
}

mount_dir="${mount_dir%/}"
output_root="${output_root%/}"

[ -n "$mount_dir" ] || fail "--mount is required"
[ -d "$mount_dir" ] || fail "mount directory does not exist: $mount_dir"

mount_dir_real="$(physical_dir "$mount_dir")" || fail "cannot resolve mount directory: $mount_dir"
[ "$mount_dir_real" != "/" ] || fail "refusing to collect from /"

report_dir="$output_root/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$report_dir"

if "$repo_root/scripts/atomcam2-check-sd-payload.sh" "$mount_dir" > "$report_dir/check-sd-payload.txt" 2>&1; then
  verify_status=0
else
  verify_status=$?
fi

for path in \
  atomcam2-init-entered.env \
  atomcam2-initramfs.env \
  atomcam2-pre-run.env \
  atomcam2-network.env \
  atomcam2-wifi-driver.env \
  nerves-provisioning.conf \
  hostname \
  authorized_keys; do
  copy_if_present "$path" "$report_dir" >> "$report_dir/collect.log"
done

cat > "$report_dir/README.md" <<REPORT
# AtomCam2 first-boot report collection

Source mount: $mount_dir
Collected at: $(date)
SD payload check exit status: $verify_status

These files are copied from the AtomCam2 SD-card FAT partition after a hardware
boot attempt. Missing later-stage files usually indicate that boot stopped before
that layer.

Expected order:

1. atomcam2-init-entered.env
2. atomcam2-initramfs.env
3. atomcam2-pre-run.env
4. atomcam2-wifi-driver.env
5. atomcam2-network.env
REPORT

printf 'Collected AtomCam2 first-boot report files into: %s\n' "$report_dir"
