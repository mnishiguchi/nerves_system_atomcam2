#!/bin/sh
set -eu

TARGET_DIR="$1"

if [ -L "$TARGET_DIR/data" ]; then
  rm "$TARGET_DIR/data"
elif [ -d "$TARGET_DIR/data" ]; then
  :
elif [ -e "$TARGET_DIR/data" ]; then
  echo "data mount point is not a directory: $TARGET_DIR/data" >&2
  exit 1
else
  :
fi

mkdir -p "$TARGET_DIR/data"
mkdir -p "$TARGET_DIR/mnt/boot-manager"
mkdir -p "$TARGET_DIR/root"
mkdir -p "$TARGET_DIR/atom"
mkdir -p "$TARGET_DIR/boot"
mkdir -p "$TARGET_DIR/media/mmc/root"
mkdir -p "$TARGET_DIR/var/run"

# Keep a visible marker for field debugging.
cat >"$TARGET_DIR/etc/atomcam2-nerves-release" <<'EOF'
nerves_system_atomcam2 experimental rootfs
EOF

# Wrap the real Nerves /sbin/init only for early bring-up breadcrumbs.
# Buildroot overlays run before post-build scripts, so this preserves the real
# erlinit binary as /sbin/init.real and installs a small shell wrapper as
# /sbin/init.
init_path="$TARGET_DIR/sbin/init"
real_init_path="$TARGET_DIR/sbin/init.real"

if [ -x "$init_path" ]; then
  if [ ! -e "$real_init_path" ]; then
    mv "$init_path" "$real_init_path"
  fi
fi

cat >"$init_path" <<'EOF'
#!/bin/sh

write_boot_note() {
  output_path="$1"

  {
    echo "stage=sbin_init_entered"
    echo "cmdline=$(cat /proc/cmdline 2>/dev/null || true)"
    echo "mounts_begin"
    cat /proc/mounts 2>/dev/null || true
    echo "mounts_end"
  } > "$output_path" 2>/dev/null || true
}

write_boot_note /media/mmc/atomcam2-sbin-init.env
write_boot_note /media/mmc/root/atomcam2-sbin-init.env
write_boot_note /boot/atomcam2-sbin-init.env
write_boot_note /tmp/atomcam2-sbin-init.env

exec /sbin/init.real "$@"
EOF

chmod 0755 "$init_path"
