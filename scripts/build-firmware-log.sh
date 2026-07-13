#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
. "$repo_dir/scripts/logging.sh"
app_dir="$repo_dir/examples/atomcam2_nerves_app"
log_dir="$(atomcam2_prepare_log_dir "$repo_dir")"
timestamp="$(date +%Y%m%d-%H%M%S)"
log_file="$log_dir/mix-firmware-$timestamp.log"

if [ ! -d "$app_dir" ]; then
  echo "missing example app directory: $app_dir" >&2
  exit 1
fi

mix_target="${MIX_TARGET:-atomcam2}"
mix_env="${MIX_ENV:-prod}"

echo "log: $log_file"
echo "MIX_TARGET: $mix_target"
echo "MIX_ENV: $mix_env"

"$repo_dir/scripts/check-prereqs.sh"
"$repo_dir/scripts/smoke-check.sh"

(
  cd "$app_dir"
  MIX_TARGET="$mix_target" MIX_ENV="$mix_env" mix deps.get
  MIX_TARGET="$mix_target" MIX_ENV="$mix_env" mix firmware "$@"
) 2>&1 | tee "$log_file"
