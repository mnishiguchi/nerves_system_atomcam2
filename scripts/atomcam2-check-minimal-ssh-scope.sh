#!/bin/sh
set -eu

repo_dir="${1:-.}"
failures=0

grep_files() {
  find "$repo_dir" \
    -path '*/.git' -prune -o \
    -path '*/.nerves' -prune -o \
    -path '*/docs/worklog' -prune -o \
    -path '*/vendor' -prune -o \
    -path '*/target' -prune -o \
    -path '*/_build' -prune -o \
    -path '*/deps' -prune -o \
    -name '*.log' -prune -o \
    -name '*.dump' -prune -o \
    -type f -print | \
      xargs grep -Il "$1" 2>/dev/null || true
}

# ADR 0008 permits the explicit, opt-in iCamera_app compatibility runtime.
# Continue rejecting broader camera features from the core Nerves system.
for forbidden in rtsp samba webui libcallback camera-service homekit webrtc rtmp; do
  matches="$(grep_files "$forbidden" | grep -v 'atomcam2-check-minimal-ssh-scope.sh' || true)"

  if [ -n "$matches" ]; then
    echo "scope warning: found '$forbidden' references" >&2
    printf '%s\n' "$matches" >&2
    failures=$((failures + 1))
  fi
done

for required in \
  README.md \
  mix.exs \
  nerves_defconfig \
  rootfs_overlay/etc/erlinit.config \
  rootfs_overlay/usr/bin/atomcam2-env \
  rootfs_overlay/usr/bin/atomcam2-pre-run \
  rootfs_overlay/usr/bin/atomcam2-wifi-driver \
  scripts/atomcam2-package-flat-sd.sh \
  scripts/atomcam2-check-sd-payload.sh \
  examples/atomcam2_nerves_app/mix.exs; do
  if [ -f "$repo_dir/$required" ]; then
    echo "ok: $required"
  else
    echo "missing: $required" >&2
    failures=$((failures + 1))
  fi
done

if [ "$failures" -gt 0 ]; then
  exit 1
fi

echo "ok: minimal ping/SSH scope looks clean"
