#!/bin/sh
set -eu

mount_dir=""
release_zip=""
release_tag="latest"
backup_dir=""
force="0"
keep_download="0"

usage() {
  cat <<'USAGE'
Usage:
  prepare-atomcam-tools-control.sh --mount PATH [OPTIONS]

Prepare a mounted AtomCam2 microSD card with atomcam_tools release files for a
control boot test.

Options:
  --mount PATH       Mounted FAT/FAT32 SD-card partition, for example:
                     /media/mnishiguchi/ATOMCAM2
  --zip PATH         Use an already downloaded atomcam_tools release zip.
  --tag TAG          GitHub release tag to download. Default: latest
                     Example: Ver.2.5.19
  --backup-dir PATH  Backup destination. Default:
                     target/atomcam2-control-backups/YYYYMMDD-HHMMSS
  --force            Actually replace SD-card contents. Without this, only show
                     what would be done.
  --keep-download    Keep downloaded/extracted release files under target/.
  -h, --help         Show this help.

Examples:
  scripts/prepare-atomcam-tools-control.sh \
    --mount /media/mnishiguchi/ATOMCAM2 \
    --force

  scripts/prepare-atomcam-tools-control.sh \
    --mount /media/mnishiguchi/ATOMCAM2 \
    --zip ~/Downloads/atomcam_tools.zip \
    --force
USAGE
}

fail() {
  echo "failed: $*" >&2
  exit 1
}

info() {
  echo "info: $*"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --mount)
      if [ "$#" -lt 2 ]; then
        fail "--mount requires a path"
      else
        mount_dir="$2"
        shift 2
      fi
      ;;
    --zip)
      if [ "$#" -lt 2 ]; then
        fail "--zip requires a path"
      else
        release_zip="$2"
        shift 2
      fi
      ;;
    --tag)
      if [ "$#" -lt 2 ]; then
        fail "--tag requires a release tag"
      else
        release_tag="$2"
        shift 2
      fi
      ;;
    --backup-dir)
      if [ "$#" -lt 2 ]; then
        fail "--backup-dir requires a path"
      else
        backup_dir="$2"
        shift 2
      fi
      ;;
    --force)
      force="1"
      shift
      ;;
    --keep-download)
      keep_download="1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

if [ -z "$mount_dir" ]; then
  usage >&2
  fail "--mount is required"
fi

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
work_root="$repo_root/target/atomcam2-atomcam-tools-control"
timestamp="$(date +%Y%m%d-%H%M%S)"

if [ -z "$backup_dir" ]; then
  backup_dir="$repo_root/target/atomcam2-control-backups/$timestamp"
fi

validate_mount_dir() {
  if [ ! -d "$mount_dir" ]; then
    fail "mount directory does not exist: $mount_dir"
  fi

  if ! mountpoint -q "$mount_dir"; then
    fail "not a mount point: $mount_dir"
  fi

  case "$mount_dir" in
    /media/*|/run/media/*|/mnt/*)
      ;;
    *)
      fail "refusing unusual mount path: $mount_dir"
      ;;
  esac

  if [ "$mount_dir" = "/" ]; then
    fail "refusing to use / as mount directory"
  fi

  if [ "$mount_dir" = "$HOME" ]; then
    fail "refusing to use HOME as mount directory"
  fi
}

download_release_zip() {
  mkdir -p "$work_root"

  if [ -n "$release_zip" ]; then
    if [ ! -f "$release_zip" ]; then
      fail "release zip not found: $release_zip"
    fi
    printf '%s\n' "$release_zip"
    return 0
  fi

  output_zip="$work_root/atomcam_tools-${release_tag}.zip"

  python3 - "$release_tag" "$output_zip" <<'PY'
import json
import sys
import urllib.request
from pathlib import Path

tag = sys.argv[1]
out_path = Path(sys.argv[2])

if tag == "latest":
    api_url = "https://api.github.com/repos/mnakada/atomcam_tools/releases/latest"
else:
    api_url = f"https://api.github.com/repos/mnakada/atomcam_tools/releases/tags/{tag}"

request = urllib.request.Request(
    api_url,
    headers={"Accept": "application/vnd.github+json", "User-Agent": "atomcam2-control-script"},
)

with urllib.request.urlopen(request) as response:
    release = json.load(response)

assets = release.get("assets", [])
zip_assets = []

for asset in assets:
    name = asset.get("name", "")
    download_url = asset.get("browser_download_url", "")

    if name.endswith(".zip") and "source" not in name.lower():
        zip_assets.append((name, download_url))

preferred = []
for name, download_url in zip_assets:
    if "atomcam_tools" in name:
        preferred.append((name, download_url))

if preferred:
    selected_name, selected_url = preferred[0]
elif zip_assets:
    selected_name, selected_url = zip_assets[0]
else:
    names = [asset.get("name", "") for asset in assets]
    raise SystemExit(f"failed: no release zip asset found. assets={names}")

print(f"info: selected release asset: {selected_name}", file=sys.stderr)

with urllib.request.urlopen(selected_url) as response:
    data = response.read()

out_path.write_bytes(data)
print(out_path)
PY
}

extract_release() {
  zip_path="$1"
  extract_dir="$work_root/extracted-$timestamp"

  rm -rf "$extract_dir"
  mkdir -p "$extract_dir"

  python3 - "$zip_path" "$extract_dir" <<'PY'
import sys
import zipfile
from pathlib import Path

zip_path = Path(sys.argv[1])
extract_dir = Path(sys.argv[2])

with zipfile.ZipFile(zip_path) as archive:
    archive.extractall(extract_dir)
PY

  printf '%s\n' "$extract_dir"
}

find_payload_dir() {
  extract_dir="$1"

  payload_dir="$(find "$extract_dir" -type f -name factory_t31_ZMC6tiIDQN -printf '%h\n' | head -1)"

  if [ -z "$payload_dir" ]; then
    echo "failed: factory_t31_ZMC6tiIDQN not found under extracted release" >&2
    echo "debug: top-level extracted files:" >&2
    find "$extract_dir" -maxdepth 3 -type f | sort | sed 's/^/  /' >&2
    exit 1
  fi

  if [ ! -f "$payload_dir/rootfs_hack.squashfs" ]; then
    echo "failed: rootfs_hack.squashfs not found next to factory_t31_ZMC6tiIDQN" >&2
    echo "debug: payload candidate: $payload_dir" >&2
    find "$payload_dir" -maxdepth 2 -type f | sort | sed 's/^/  /' >&2
    exit 1
  fi

  printf '%s\n' "$payload_dir"
}

backup_mount_contents() {
  mkdir -p "$backup_dir"

  info "backing up SD contents to: $backup_dir"

  if command -v rsync >/dev/null 2>&1; then
    rsync -a -- "$mount_dir"/ "$backup_dir"/
  else
    (cd "$mount_dir" && tar cf - .) | (cd "$backup_dir" && tar xf -)
  fi
}

clear_mount_contents() {
  info "removing current SD contents from: $mount_dir"
  find "$mount_dir" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
}

copy_payload() {
  payload_dir="$1"

  info "copying atomcam_tools payload from: $payload_dir"

  if command -v rsync >/dev/null 2>&1; then
    rsync -a -- "$payload_dir"/ "$mount_dir"/
  else
    (cd "$payload_dir" && tar cf - .) | (cd "$mount_dir" && tar xf -)
  fi

  sync
}

verify_mount_payload() {
  missing="0"

  for required_file in factory_t31_ZMC6tiIDQN rootfs_hack.squashfs hostname; do
    if [ -f "$mount_dir/$required_file" ]; then
      info "ok: $required_file"
    else
      echo "failed: missing $required_file" >&2
      missing="1"
    fi
  done

  if [ "$missing" = "1" ]; then
    fail "atomcam_tools payload is incomplete on SD card"
  fi

  info "SD card is ready for atomcam_tools control boot: $mount_dir"
}

validate_mount_dir
zip_path="$(download_release_zip)"
extract_dir="$(extract_release "$zip_path")"
payload_dir="$(find_payload_dir "$extract_dir")"

info "mount: $mount_dir"
info "release zip: $zip_path"
info "payload dir: $payload_dir"
info "backup dir: $backup_dir"

if [ "$force" != "1" ]; then
  echo
  echo "dry run only. Re-run with --force to replace SD-card contents."
  echo
  echo "Example:"
  echo "  scripts/prepare-atomcam-tools-control.sh --mount '$mount_dir' --force"
  exit 0
fi

backup_mount_contents
clear_mount_contents
copy_payload "$payload_dir"
verify_mount_payload

if [ "$keep_download" != "1" ]; then
  rm -rf "$work_root/extracted-$timestamp"
fi

cat <<EOF2

Next:
  1. Unmount the SD card cleanly.
  2. Insert it into AtomCam2.
  3. Power on and check whether atomcam_tools changes the camera behavior.

Restore Nerves payload later from:
  $backup_dir
EOF2
