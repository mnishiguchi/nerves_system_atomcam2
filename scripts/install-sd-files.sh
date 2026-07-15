#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mix_target="${MIX_TARGET:-atomcam2}"
mix_env="${MIX_ENV:-prod}"
source_dir="$repo_root/examples/atomcam2_nerves_app/_build/${mix_target}_${mix_env}/nerves/images/atomcam2-sd"
mount_dir=""
dry_run=0
force=0
backup=1

usage() {
  cat <<'USAGE'
Usage: scripts/install-sd-files.sh --mount MOUNT_DIR [options]

Copy generated AtomCam2 SD-card files to a mounted FAT partition.

Options:
  --source DIR     Source directory. Default: final app payload for MIX_TARGET/MIX_ENV
  --mount DIR      Mounted AtomCam2 SD-card FAT partition
  --force          Allow overwriting existing AtomCam2 files
  --dry-run        Print actions without copying
  --no-backup      Do not back up overwritten files
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
    --source)
      require_option_value "$1" "${2:-}"
      source_dir="$2"
      shift 2
      ;;
    --mount)
      require_option_value "$1" "${2:-}"
      mount_dir="$2"
      shift 2
      ;;
    --force)
      force=1
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --no-backup)
      backup=0
      shift
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

copy_file() {
  local source_file="$1"
  local destination_file="$2"

  if [ "$dry_run" -eq 1 ]; then
    echo "copy: $source_file -> $destination_file"
  else
    cp -f "$source_file" "$destination_file"
  fi
}

maybe_backup_file() {
  local destination_file="$1"

  if [ ! -e "$destination_file" ]; then
    return 0
  fi

  if [ "$force" -ne 1 ]; then
    fail "destination already has $(basename "$destination_file"); pass --force to overwrite"
  fi

  if [ "$backup" -ne 1 ]; then
    return 0
  fi

  if [ "$dry_run" -eq 1 ]; then
    echo "backup: $destination_file -> $backup_dir/$(basename "$destination_file")"
  else
    mkdir -p "$backup_dir"
    cp -a "$destination_file" "$backup_dir/$(basename "$destination_file")"
  fi
}

source_dir="${source_dir%/}"
mount_dir="${mount_dir%/}"

[ -n "$mount_dir" ] || fail "--mount is required"
[ "$mount_dir" != "/" ] || fail "refusing to install to /"
[ -d "$source_dir" ] || fail "source directory does not exist: $source_dir"
[ -d "$mount_dir" ] || fail "mount directory does not exist: $mount_dir"

source_dir_real="$(physical_dir "$source_dir")" || fail "cannot resolve source directory: $source_dir"
mount_dir_real="$(physical_dir "$mount_dir")" || fail "cannot resolve mount directory: $mount_dir"
[ "$source_dir_real" != "$mount_dir_real" ] || fail "source and mount directories must differ"

"$repo_root/scripts/atomcam2-check-sd-payload.sh" "$source_dir"

write_test="$mount_dir/.atomcam2-write-test.$$"
if [ "$dry_run" -ne 1 ]; then
  if ! : > "$write_test" 2>/dev/null; then
    fail "mount directory is not writable: $mount_dir"
  fi
  rm -f "$write_test"
fi

backup_dir="$mount_dir/atomcam2-backup-$(date +%Y%m%d%H%M%S)"

files="
factory_t31_ZMC6tiIDQN
rootfs_hack.squashfs
hostname
authorized_keys
nerves-provisioning.conf
"

for file in $files; do
  if [ -f "$source_dir/$file" ]; then
    maybe_backup_file "$mount_dir/$file"
    copy_file "$source_dir/$file" "$mount_dir/$file"
  fi
done

if [ "$dry_run" -eq 1 ]; then
  echo "atomcam2 sd install: dry run completed"
  exit 0
fi

sync
"$repo_root/scripts/atomcam2-check-sd-payload.sh" "$mount_dir"

echo "atomcam2 sd install: installed AtomCam2 SD-card files to: $mount_dir"

if [ -d "$backup_dir" ]; then
  echo "atomcam2 sd install: backup written to: $backup_dir"
fi
