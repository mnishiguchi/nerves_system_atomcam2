#!/bin/sh
set -eu

script_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
metadata_script="$script_dir/atomcam2-boot-metadata.sh"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

assert_equal() {
  expected="$1"
  actual="$2"
  description="$3"

  if [ "$actual" = "$expected" ]; then
    echo "ok: $description"
  else
    echo "error: $description" >&2
    echo "expected: $expected" >&2
    echo "actual:   $actual" >&2
    exit 1
  fi
}

slot_a_uuid="11111111-1111-4111-8111-111111111111"
slot_a_sha="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
slot_b_uuid="22222222-2222-4222-8222-222222222222"
slot_b_sha="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
record_a="$test_root/a.bin"
record_b="$test_root/b.bin"

"$metadata_script" write \
  "$record_a" \
  00000000000000000001 \
  A - 000 003 \
  valid "$slot_a_uuid" "$slot_a_sha" \
  empty - -

echo "ok: write initial record"

assert_equal \
  4096 \
  "$(wc -c < "$record_a" | awk '{print $1}')" \
  "fixed record size"

read_output="$("$metadata_script" read "$record_a")"

printf '%s\n' "$read_output" |
  grep -q '^generation=00000000000000000001$'

echo "ok: read initial record"

"$metadata_script" write \
  "$record_b" \
  00000000000000000002 \
  A B 001 003 \
  valid "$slot_a_uuid" "$slot_a_sha" \
  valid "$slot_b_uuid" "$slot_b_sha"

echo "ok: write newer record"

assert_equal \
  "$record_b" \
  "$("$metadata_script" select "$record_a" "$record_b")" \
  "select newer record"

corrupt_a="$test_root/a-corrupt.bin"

cp "$record_a" "$corrupt_a"

printf X |
  dd \
    of="$corrupt_a" \
    bs=1 \
    seek=0 \
    count=1 \
    conv=notrunc \
    2>/dev/null

assert_equal \
  "$record_b" \
  "$("$metadata_script" select "$corrupt_a" "$record_b")" \
  "ignore corrupt record"

corrupt_b="$test_root/b-corrupt.bin"

cp "$record_b" "$corrupt_b"

printf X |
  dd \
    of="$corrupt_b" \
    bs=1 \
    seek=0 \
    count=1 \
    conv=notrunc \
    2>/dev/null

if "$metadata_script" \
  select \
  "$corrupt_a" \
  "$corrupt_b" \
  >/dev/null \
  2>&1; then

  echo "error: accepted two corrupt records" >&2
  exit 1
else
  echo "ok: reject two corrupt records"
fi

record_a_copy="$test_root/a-copy.bin"

cp "$record_a" "$record_a_copy"

assert_equal \
  "$record_a" \
  "$("$metadata_script" select "$record_a" "$record_a_copy")" \
  "select first identical record"

conflict_a="$test_root/conflict-a.bin"
conflict_b="$test_root/conflict-b.bin"

"$metadata_script" write \
  "$conflict_a" \
  00000000000000000003 \
  A - 000 003 \
  valid "$slot_a_uuid" "$slot_a_sha" \
  valid "$slot_b_uuid" "$slot_b_sha"

"$metadata_script" write \
  "$conflict_b" \
  00000000000000000003 \
  A B 001 003 \
  valid "$slot_a_uuid" "$slot_a_sha" \
  valid "$slot_b_uuid" "$slot_b_sha"

if "$metadata_script" \
  select \
  "$conflict_a" \
  "$conflict_b" \
  >/dev/null \
  2>&1; then

  echo "error: accepted equal-generation conflict" >&2
  exit 1
else
  echo "ok: reject equal-generation conflict"
fi

if "$metadata_script" write \
  "$test_root/invalid.bin" \
  00000000000000000004 \
  A - 001 003 \
  valid "$slot_a_uuid" "$slot_a_sha" \
  empty - - \
  >/dev/null \
  2>&1; then

  echo "error: accepted attempts without pending slot" >&2
  exit 1
else
  echo "ok: reject attempts without pending slot"
fi

checksum_corrupt="$test_root/checksum-corrupt.bin"

cp "$record_b" "$checksum_corrupt"

printf 9 |
  dd \
    of="$checksum_corrupt" \
    bs=1 \
    seek=40 \
    count=1 \
    conv=notrunc \
    2>/dev/null

if "$metadata_script" \
  read \
  "$checksum_corrupt" \
  >/dev/null \
  2>&1; then

  echo "error: accepted checksum corruption" >&2
  exit 1
else
  echo "ok: reject checksum corruption"
fi

invalid_uuid="1111111--1111-4111-8111-111111111111"

if "$metadata_script" write \
  "$test_root/invalid-uuid.bin" \
  00000000000000000005 \
  A - 000 003 \
  valid "$invalid_uuid" "$slot_a_sha" \
  empty - - \
  >/dev/null \
  2>&1; then

  echo "error: accepted malformed firmware UUID" >&2
  exit 1
else
  echo "ok: reject malformed firmware UUID"
fi


known_sha256="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

assert_equal \
  "aaaaaaaa-aaaa-5aaa-8aaa-aaaaaaaaaaaa" \
  "$("$metadata_script" firmware-id "$known_sha256")" \
  "derive deterministic firmware ID"

initial_rootfs="$test_root/initial-rootfs.squashfs"
initial_record="$test_root/initial-record.bin"

printf 'AtomCam2 initial rootfs test\n' > "$initial_rootfs"

"$metadata_script" \
  initial-record \
  "$initial_record" \
  "$initial_rootfs"

initial_output="$(
  "$metadata_script" read "$initial_record"
)"

initial_generation="$(
  printf '%s\n' "$initial_output" |
    awk -F= '$1 == "generation" { print $2 }'
)"

initial_confirmed_slot="$(
  printf '%s\n' "$initial_output" |
    awk -F= '$1 == "confirmed_slot" { print $2 }'
)"

initial_pending_slot="$(
  printf '%s\n' "$initial_output" |
    awk -F= '$1 == "pending_slot" { print $2 }'
)"

initial_slot_a_sha256="$(
  printf '%s\n' "$initial_output" |
    awk -F= '$1 == "slot_a_sha256" { print $2 }'
)"

initial_slot_a_firmware_id="$(
  printf '%s\n' "$initial_output" |
    awk -F= '$1 == "slot_a_firmware_id" { print $2 }'
)"

initial_slot_b_status="$(
  printf '%s\n' "$initial_output" |
    awk -F= '$1 == "slot_b_status" { print $2 }'
)"

expected_initial_sha256="$(
  sha256sum "$initial_rootfs" |
    awk '{print $1}'
)"

expected_initial_firmware_id="$(
  "$metadata_script" firmware-id "$expected_initial_sha256"
)"

assert_equal \
  4096 \
  "$(wc -c < "$initial_record" | awk '{print $1}')" \
  "initial record size"

assert_equal \
  00000000000000000001 \
  "$initial_generation" \
  "initial generation"

assert_equal \
  A \
  "$initial_confirmed_slot" \
  "initial confirmed slot"

assert_equal \
  - \
  "$initial_pending_slot" \
  "initial pending slot"

assert_equal \
  "$expected_initial_sha256" \
  "$initial_slot_a_sha256" \
  "initial slot A checksum"

assert_equal \
  "$expected_initial_firmware_id" \
  "$initial_slot_a_firmware_id" \
  "initial slot A firmware ID"

assert_equal \
  empty \
  "$initial_slot_b_status" \
  "initial slot B status"

echo "ok: initial boot metadata record"

device_image="$test_root/device.bin"
device_work_directory="$test_root/device-work"

dd \
  if=/dev/zero \
  of="$device_image" \
  bs=512 \
  count=2048 \
  2>/dev/null

dd \
  if="$record_a" \
  of="$device_image" \
  bs=512 \
  seek=2032 \
  count=8 \
  conv=notrunc \
  2>/dev/null

dd \
  if="$record_b" \
  of="$device_image" \
  bs=512 \
  seek=2040 \
  count=8 \
  conv=notrunc \
  2>/dev/null

device_output="$(
  "$metadata_script" \
    select-device \
    "$device_image" \
    "$device_work_directory"
)"

selected_copy="$(
  printf '%s\n' "$device_output" |
    awk -F= '$1 == "selected_copy" { print $2 }'
)"

selected_generation="$(
  printf '%s\n' "$device_output" |
    awk -F= '$1 == "generation" { print $2 }'
)"

assert_equal \
  B \
  "$selected_copy" \
  "select newer raw-device copy"

assert_equal \
  00000000000000000002 \
  "$selected_generation" \
  "read raw-device generation"

printf X |
  dd \
    of="$device_image" \
    bs=512 \
    seek=2040 \
    count=1 \
    conv=notrunc \
    2>/dev/null

device_output="$(
  "$metadata_script" \
    select-device \
    "$device_image" \
    "$device_work_directory"
)"

selected_copy="$(
  printf '%s\n' "$device_output" |
    awk -F= '$1 == "selected_copy" { print $2 }'
)"

assert_equal \
  A \
  "$selected_copy" \
  "fall back from corrupt raw-device copy"

echo "ok: raw-device metadata selection"
echo "ok: rollback metadata tests"
