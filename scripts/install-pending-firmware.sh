#!/bin/sh
set -eu

PATH=/sbin:/bin:/usr/sbin:/usr/bin
export PATH

usage() {
  printf '%s\n' \
    "Usage:" \
    "  ATOMCAM2_CONFIRM_DEVICE=/dev/sdX $0 FIRMWARE DEVICE"
}

metadata_value() {
  key="$1"
  input_path="$2"

  awk \
    -F= \
    -v key="$key" '
      $1 == key {
        value = $2
      }

      END {
        if (value == "") {
          exit 1
        }

        print value
      }
    ' \
    "$input_path"
}

increment_generation() {
  generation="$1"

  awk \
    -v generation="$generation" '
      BEGIN {
        if (length(generation) != 20 || generation ~ /[^0-9]/) {
          exit 1
        }

        result = generation
        carry = 1

        for (position = 20; position >= 1; position--) {
          digit = substr(result, position, 1) + 0

          if (digit < 9) {
            digit += 1
            result = \
              substr(result, 1, position - 1) \
              digit \
              substr(result, position + 1)
            carry = 0
            break
          }

          result = \
            substr(result, 1, position - 1) \
            "0" \
            substr(result, position + 1)
        }

        if (carry != 0) {
          exit 1
        }

        print result
      }
    '
}

partition_path() {
  device_path="$1"
  partition_number="$2"

  case "$device_path" in
    *[0-9])
      printf '%sp%s\n' "$device_path" "$partition_number"
      ;;
    *)
      printf '%s%s\n' "$device_path" "$partition_number"
      ;;
  esac
}

if [ "$#" -ne 2 ]; then
  usage >&2
  exit 1
fi

firmware_path="$1"
device_path="$2"

if [ "$(id -u)" -ne 0 ]; then
  printf 'error: run this script as root\n' >&2
  exit 1
fi

if [ ! -f "$firmware_path" ]; then
  printf 'error: firmware not found: %s\n' "$firmware_path" >&2
  exit 1
fi

if [ ! -b "$device_path" ]; then
  printf 'error: block device not found: %s\n' "$device_path" >&2
  exit 1
fi

if [ "${ATOMCAM2_CONFIRM_DEVICE:-}" != "$device_path" ]; then
  printf '%s\n' \
    "error: refusing to modify $device_path" \
    "set ATOMCAM2_CONFIRM_DEVICE=$device_path to confirm" >&2
  exit 1
fi

if lsblk -nrpo MOUNTPOINT "$device_path" |
  awk 'NF && $0 != "" { found = 1 } END { exit !found }'
then
  printf 'error: device or one of its partitions is mounted: %s\n' \
    "$device_path" >&2
  exit 1
fi

script_directory="$(
  CDPATH='' cd -- "$(dirname -- "$0")" &&
    pwd
)"

metadata_script="$script_directory/atomcam2-boot-metadata.sh"

if [ ! -x "$metadata_script" ]; then
  printf 'error: metadata script is not executable: %s\n' \
    "$metadata_script" >&2
  exit 1
fi

work_directory="$(
  mktemp -d "${TMPDIR:-/tmp}/atomcam2-pending-firmware.XXXXXX"
)"

cleanup() {
  rm -rf "$work_directory"
}

trap cleanup EXIT HUP INT TERM

rootfs_path="$work_directory/rootfs.img"
metadata_state_path="$work_directory/metadata-state"
next_record_path="$work_directory/next-record"
verified_rootfs_path="$work_directory/verified-rootfs.img"

if ! unzip -p "$firmware_path" data/rootfs.img > "$rootfs_path"; then
  printf 'error: failed to extract data/rootfs.img\n' >&2
  exit 1
fi

if [ ! -s "$rootfs_path" ]; then
  printf 'error: extracted rootfs.img is empty\n' >&2
  exit 1
fi

"$metadata_script" \
  select-device \
  "$device_path" \
  "$work_directory" > "$metadata_state_path"

selected_copy="$(metadata_value selected_copy "$metadata_state_path")"
generation="$(metadata_value generation "$metadata_state_path")"
confirmed_slot="$(metadata_value confirmed_slot "$metadata_state_path")"
pending_slot="$(metadata_value pending_slot "$metadata_state_path")"
max_attempts="$(metadata_value max_attempts "$metadata_state_path")"

slot_a_status="$(metadata_value slot_a_status "$metadata_state_path")"
slot_a_firmware_id="$(
  metadata_value slot_a_firmware_id "$metadata_state_path"
)"
slot_a_sha256="$(metadata_value slot_a_sha256 "$metadata_state_path")"

slot_b_status="$(metadata_value slot_b_status "$metadata_state_path")"
slot_b_firmware_id="$(
  metadata_value slot_b_firmware_id "$metadata_state_path"
)"
slot_b_sha256="$(metadata_value slot_b_sha256 "$metadata_state_path")"

if [ "$pending_slot" != "-" ]; then
  printf 'error: a pending slot already exists: %s\n' "$pending_slot" >&2
  exit 1
fi

case "$confirmed_slot" in
  A)
    candidate_slot="B"
    candidate_partition="$(partition_path "$device_path" 3)"
    ;;
  B)
    candidate_slot="A"
    candidate_partition="$(partition_path "$device_path" 2)"
    ;;
  *)
    printf 'error: invalid confirmed slot: %s\n' "$confirmed_slot" >&2
    exit 1
    ;;
esac

if [ ! -b "$candidate_partition" ]; then
  printf 'error: candidate partition not found: %s\n' \
    "$candidate_partition" >&2
  exit 1
fi

rootfs_size="$(wc -c < "$rootfs_path" | tr -d ' ')"
partition_size="$(blockdev --getsize64 "$candidate_partition")"

if [ "$rootfs_size" -gt "$partition_size" ]; then
  printf 'error: rootfs does not fit in %s\n' "$candidate_partition" >&2
  exit 1
fi

rootfs_sha256="$(
  sha256sum "$rootfs_path" |
    awk '{print $1}'
)"

rootfs_firmware_id="$(
  "$metadata_script" firmware-id "$rootfs_sha256"
)"

next_generation="$(increment_generation "$generation")"

case "$candidate_slot" in
  A)
    slot_a_status="valid"
    slot_a_firmware_id="$rootfs_firmware_id"
    slot_a_sha256="$rootfs_sha256"
    ;;
  B)
    slot_b_status="valid"
    slot_b_firmware_id="$rootfs_firmware_id"
    slot_b_sha256="$rootfs_sha256"
    ;;
esac

"$metadata_script" write \
  "$next_record_path" \
  "$next_generation" \
  "$confirmed_slot" \
  "$candidate_slot" \
  000 \
  "$max_attempts" \
  "$slot_a_status" \
  "$slot_a_firmware_id" \
  "$slot_a_sha256" \
  "$slot_b_status" \
  "$slot_b_firmware_id" \
  "$slot_b_sha256"

printf '%s\n' \
  "confirmed_slot=$confirmed_slot" \
  "candidate_slot=$candidate_slot" \
  "candidate_partition=$candidate_partition" \
  "candidate_firmware_id=$rootfs_firmware_id" \
  "candidate_sha256=$rootfs_sha256" \
  "next_generation=$next_generation"

dd \
  if="$rootfs_path" \
  of="$candidate_partition" \
  bs=4M \
  conv=fsync \
  status=progress

head \
  -c "$rootfs_size" \
  "$candidate_partition" > "$verified_rootfs_path"

verified_rootfs_sha256="$(
  sha256sum "$verified_rootfs_path" |
    awk '{print $1}'
)"

if [ "$verified_rootfs_sha256" != "$rootfs_sha256" ]; then
  printf 'error: candidate partition verification failed\n' >&2
  exit 1
fi

case "$selected_copy" in
  A)
    written_copy="B"
    metadata_sector=2040
    ;;
  B)
    written_copy="A"
    metadata_sector=2032
    ;;
  *)
    printf 'error: invalid selected metadata copy: %s\n' \
      "$selected_copy" >&2
    exit 1
    ;;
esac

dd \
  if="$next_record_path" \
  of="$device_path" \
  bs=512 \
  seek="$metadata_sector" \
  count=8 \
  conv=notrunc,fsync \
  status=none

"$metadata_script" \
  select-device \
  "$device_path" \
  "$work_directory"

printf '%s\n' \
  "pending firmware installed successfully" \
  "written_metadata_copy=$written_copy"
