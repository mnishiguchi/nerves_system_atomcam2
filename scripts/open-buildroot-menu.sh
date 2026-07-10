#!/usr/bin/env bash
set -euo pipefail

build_dir="${1:-o/atomcam2}"

if [ ! -d "$build_dir" ]; then
  echo "Build directory does not exist: $build_dir"
  echo "Build once before running menuconfig."
  exit 1
fi

make -C "$build_dir" menuconfig
make -C "$build_dir" savedefconfig
