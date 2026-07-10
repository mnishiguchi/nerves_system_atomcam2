#!/bin/sh
set -eu

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

require_file() {
  if [ -f "$repo_dir/$1" ]; then
    echo "ok: $1"
  else
    echo "missing: $1" >&2
    exit 1
  fi
}

require_executable() {
  require_file "$1"
  if [ -x "$repo_dir/$1" ]; then
    echo "ok: executable $1"
  else
    echo "not executable: $1" >&2
    exit 1
  fi
}

check_script_syntax() {
  shell_file="$1"
  first_line="$(sed -n '1p' "$shell_file")"

  case "$first_line" in
    *bash*) bash -n "$shell_file" ;;
    *) sh -n "$shell_file" ;;
  esac

  echo "ok: syntax ${shell_file#$repo_dir/}"
}

require_file README.md
require_file mix.exs
require_file nerves_defconfig
require_file linux-3.10.14.defconfig
require_file busybox.fragment
require_file Config.in
require_file package/Config.in
require_file external.desc
require_file external.mk
require_file board/atomcam2/initramfs/init
require_file rootfs_overlay/etc/erlinit.config
require_file rootfs_overlay/etc/atomcam2.env
require_executable rootfs_overlay/usr/bin/atomcam2-env
require_executable rootfs_overlay/usr/bin/atomcam2-pre-run
require_executable rootfs_overlay/usr/bin/atomcam2-wifi-driver
require_executable rootfs_overlay/usr/bin/atomcam2-network-check
require_executable scripts/atomcam2-package-flat-sd.sh
require_executable scripts/atomcam2-check-sd-payload.sh
require_executable scripts/atomcam2-check-minimal-ssh-scope.sh
require_file examples/atomcam2_nerves_app/mix.exs
require_file examples/atomcam2_nerves_app/lib/atomcam2_nerves_app/application.ex
require_file examples/atomcam2_nerves_app/lib/atomcam2_nerves_app/network.ex

find "$repo_dir" \
  -path '*/.git' -prune -o \
  -path '*/vendor' -prune -o \
  \( -name '*.sh' -o -path '*/usr/bin/atomcam2-*' -o -path '*/initramfs/init' \) \
  -type f -print | while IFS= read -r shell_file; do
  check_script_syntax "$shell_file"
done

"$repo_dir/scripts/atomcam2-check-minimal-ssh-scope.sh" "$repo_dir"
