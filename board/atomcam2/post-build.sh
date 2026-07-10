#!/bin/sh
set -eu

TARGET_DIR="$1"

mkdir -p "$TARGET_DIR/data"
mkdir -p "$TARGET_DIR/root"
mkdir -p "$TARGET_DIR/atom"
mkdir -p "$TARGET_DIR/boot"
mkdir -p "$TARGET_DIR/media/mmc/root"
mkdir -p "$TARGET_DIR/var/run"

# Keep a visible marker for field debugging.
cat > "$TARGET_DIR/etc/atomcam2-nerves-release" <<'EOF'
nerves_system_atomcam2 experimental rootfs
EOF
