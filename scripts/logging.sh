#!/bin/sh

atomcam2_repo_root() {
  CDPATH= cd -- "$(dirname -- "$0")/.." && pwd
}

atomcam2_log_dir() {
  repo_root="${1:-$(atomcam2_repo_root)}"

  if [ -n "${ATOMCAM2_LOG_DIR:-}" ]; then
    printf '%s\n' "$ATOMCAM2_LOG_DIR"
  else
    printf '%s\n' "$repo_root/tmp/log"
  fi
}

atomcam2_prepare_log_dir() {
  log_dir="$(atomcam2_log_dir "${1:-}")"
  mkdir -p "$log_dir"
  printf '%s\n' "$log_dir"
}
