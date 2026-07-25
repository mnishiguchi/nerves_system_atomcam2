#!/bin/sh
set -eu

TARGET_DIR="$1"

if [ -z "${NERVES_DEFCONFIG_DIR:-}" ]; then
  echo "NERVES_DEFCONFIG_DIR is not set" >&2
  exit 1
fi

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
mkdir -p "$TARGET_DIR/usr/bin"
mkdir -p "$TARGET_DIR/usr/libexec/atomcam2"
mkdir -p "$TARGET_DIR/usr/share/fwup"

# Keep incremental system builds aligned with the current rootfs contents.
rm -f "$TARGET_DIR/usr/libexec/atomcam2/fwup-stream"

install -m 0755 \
  "$NERVES_DEFCONFIG_DIR/scripts/atomcam2-boot-metadata.sh" \
  "$TARGET_DIR/usr/bin/atomcam2-boot-metadata"

install -m 0755 \
  "$NERVES_DEFCONFIG_DIR/scripts/atomcam2-firmware-update.sh" \
  "$TARGET_DIR/usr/bin/atomcam2-firmware-update"

install -m 0755 \
  "$NERVES_DEFCONFIG_DIR/scripts/atomcam2-fwup-ops.sh" \
  "$TARGET_DIR/usr/libexec/atomcam2/fwup-ops"

cat > "$TARGET_DIR/usr/share/fwup/ops.fw" <<'EOF_OPS'
Atom Cam 2 firmware operations are handled by /usr/libexec/atomcam2/fwup-ops.
EOF_OPS

# Keep a visible marker for field debugging.
cat >"$TARGET_DIR/etc/atomcam2-nerves-release" <<'EOF_RELEASE'
nerves_system_atomcam2 experimental rootfs
EOF_RELEASE

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

cat >"$init_path" <<'EOF_INIT'
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
EOF_INIT

chmod 0755 "$init_path"
