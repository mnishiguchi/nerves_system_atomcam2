#!/bin/sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
vintage_net_if_monitor="$repo_root/examples/atomcam2_nerves_app/deps/vintage_net/src/if_monitor.c"

if [ ! -f "$vintage_net_if_monitor" ]; then
  echo "failed: VintageNet source not found: $vintage_net_if_monitor" >&2
  echo "hint: run this first:" >&2
  echo "  cd examples/atomcam2_nerves_app" >&2
  echo "  mix deps.get" >&2
  exit 1
fi

python3 - "$vintage_net_if_monitor" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

marker = "#define WORKAROUND_IFF_LOWER_UP (0x10000)\n"

old_compat_block = """#define WORKAROUND_IFF_LOWER_UP (0x10000)

/*
 * Linux 3.10 headers used by the AtomCam2 bring-up do not define IFA_FLAGS.
 * VintageNet can still build for this MVP when the netlink attribute number is
 * provided here.
 */
#ifndef IFA_FLAGS
#define IFA_FLAGS 8
#endif
"""

compat_block = """#define WORKAROUND_IFF_LOWER_UP (0x10000)

/*
 * Linux 3.10 headers used by AtomCam2 do not define IFA_FLAGS.
 *
 * IFA_MAX must be expanded at the same time. VintageNet indexes an attribute
 * array using IFA_FLAGS, so defining IFA_FLAGS without updating IFA_MAX causes
 * an out-of-bounds access.
 */
#ifndef IFA_FLAGS
#define IFA_FLAGS 8
#undef IFA_MAX
#define IFA_MAX IFA_FLAGS
#endif
"""

if compat_block in text:
    print(f"ok: already patched: {path}")
elif old_compat_block in text:
    path.write_text(text.replace(old_compat_block, compat_block, 1))
    print(f"ok: upgraded patch: {path}")
elif marker in text:
    path.write_text(text.replace(marker, compat_block, 1))
    print(f"ok: patched: {path}")
else:
    raise SystemExit(f"failed: marker not found in {path}")
PY
