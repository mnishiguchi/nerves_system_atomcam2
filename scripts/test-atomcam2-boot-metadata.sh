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


confirmed_policy_record="$test_root/policy-confirmed.bin"

"$metadata_script" write \
  "$confirmed_policy_record" \
  00000000000000000006 \
  B - 000 003 \
  valid "$slot_a_uuid" "$slot_a_sha" \
  valid "$slot_b_uuid" "$slot_b_sha"

confirmed_policy_output="$(
  "$metadata_script" \
    choose-slot \
    "$confirmed_policy_record"
)"

assert_equal \
  B \
  "$(
    printf '%s\n' "$confirmed_policy_output" |
      awk -F= '$1 == "selected_slot" { print $2 }'
  )" \
  "choose confirmed slot"

assert_equal \
  confirmed \
  "$(
    printf '%s\n' "$confirmed_policy_output" |
      awk -F= '$1 == "selection_reason" { print $2 }'
  )" \
  "report confirmed selection reason"

pending_policy_record="$test_root/policy-pending.bin"

"$metadata_script" write \
  "$pending_policy_record" \
  00000000000000000007 \
  A B 002 003 \
  valid "$slot_a_uuid" "$slot_a_sha" \
  valid "$slot_b_uuid" "$slot_b_sha"

pending_policy_output="$(
  "$metadata_script" \
    choose-slot \
    "$pending_policy_record"
)"

assert_equal \
  B \
  "$(
    printf '%s\n' "$pending_policy_output" |
      awk -F= '$1 == "selected_slot" { print $2 }'
  )" \
  "choose pending slot"

assert_equal \
  pending \
  "$(
    printf '%s\n' "$pending_policy_output" |
      awk -F= '$1 == "selection_reason" { print $2 }'
  )" \
  "report pending selection reason"

attempt_limit_record="$test_root/policy-attempt-limit.bin"

"$metadata_script" write \
  "$attempt_limit_record" \
  00000000000000000008 \
  A B 003 003 \
  valid "$slot_a_uuid" "$slot_a_sha" \
  valid "$slot_b_uuid" "$slot_b_sha"

attempt_limit_output="$(
  "$metadata_script" \
    choose-slot \
    "$attempt_limit_record"
)"

assert_equal \
  A \
  "$(
    printf '%s\n' "$attempt_limit_output" |
      awk -F= '$1 == "selected_slot" { print $2 }'
  )" \
  "fall back to confirmed slot"

assert_equal \
  pending_attempt_limit \
  "$(
    printf '%s\n' "$attempt_limit_output" |
      awk -F= '$1 == "selection_reason" { print $2 }'
  )" \
  "report pending attempt limit"

if "$metadata_script" \
  choose-slot \
  "$corrupt_a" \
  >/dev/null \
  2>&1
then
  echo "error: chose a slot from corrupt metadata" >&2
  exit 1
else
  echo "ok: reject corrupt slot-selection metadata"
fi

echo "ok: boot slot selection policy"

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


selected_slot="$(
  printf '%s\n' "$device_output" |
    awk -F= '$1 == "selected_slot" { print $2 }'
)"

selection_reason="$(
  printf '%s\n' "$device_output" |
    awk -F= '$1 == "selection_reason" { print $2 }'
)"

assert_equal \
  B \
  "$selected_slot" \
  "choose pending slot from raw device"

assert_equal \
  pending \
  "$selection_reason" \
  "report raw-device pending reason"

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


selected_slot="$(
  printf '%s\n' "$device_output" |
    awk -F= '$1 == "selected_slot" { print $2 }'
)"

selection_reason="$(
  printf '%s\n' "$device_output" |
    awk -F= '$1 == "selection_reason" { print $2 }'
)"

assert_equal \
  A \
  "$selected_slot" \
  "choose confirmed slot from fallback copy"

assert_equal \
  confirmed \
  "$selection_reason" \
  "report raw-device confirmed reason"

echo "ok: raw-device metadata selection"

mutation_device_image="$test_root/mutation-device.bin"
mutation_work_directory="$test_root/mutation-work"

dd \
  if=/dev/zero \
  of="$mutation_device_image" \
  bs=512 \
  count=2048 \
  2>/dev/null

dd \
  if="$record_a" \
  of="$mutation_device_image" \
  bs=512 \
  seek=2032 \
  count=8 \
  conv=notrunc \
  2>/dev/null

dd \
  if="$record_b" \
  of="$mutation_device_image" \
  bs=512 \
  seek=2040 \
  count=8 \
  conv=notrunc \
  2>/dev/null

selected_copy_before="$test_root/mutation-selected-before.bin"
selected_copy_after="$test_root/mutation-selected-after.bin"

dd \
  if="$mutation_device_image" \
  of="$selected_copy_before" \
  bs=512 \
  skip=2040 \
  count=8 \
  2>/dev/null

selected_copy_sha256_before="$(
  sha256sum "$selected_copy_before" |
    awk '{print $1}'
)"

mutation_output="$(
  "$metadata_script" \
    prepare-pending-image \
    "$mutation_device_image" \
    "$mutation_work_directory"
)"

assert_equal \
  B \
  "$(
    printf '%s\n' "$mutation_output" |
      awk -F= '$1 == "previous_copy" { print $2 }'
  )" \
  "identify previously selected metadata copy"

assert_equal \
  A \
  "$(
    printf '%s\n' "$mutation_output" |
      awk -F= '$1 == "written_copy" { print $2 }'
  )" \
  "write inactive metadata copy"

assert_equal \
  B \
  "$(
    printf '%s\n' "$mutation_output" |
      awk -F= '$1 == "selected_slot" { print $2 }'
  )" \
  "retain pending boot decision"

assert_equal \
  pending \
  "$(
    printf '%s\n' "$mutation_output" |
      awk -F= '$1 == "selection_reason" { print $2 }'
  )" \
  "retain pending boot reason"

assert_equal \
  00000000000000000003 \
  "$(
    printf '%s\n' "$mutation_output" |
      awk -F= '$1 == "generation" { print $2 }'
  )" \
  "increment metadata generation"

assert_equal \
  002 \
  "$(
    printf '%s\n' "$mutation_output" |
      awk -F= '$1 == "pending_attempts" { print $2 }'
  )" \
  "increment pending attempts"

dd \
  if="$mutation_device_image" \
  of="$selected_copy_after" \
  bs=512 \
  skip=2040 \
  count=8 \
  2>/dev/null

selected_copy_sha256_after="$(
  sha256sum "$selected_copy_after" |
    awk '{print $1}'
)"

assert_equal \
  "$selected_copy_sha256_before" \
  "$selected_copy_sha256_after" \
  "preserve previously selected metadata copy"

mutation_selected_output="$(
  "$metadata_script" \
    select-device \
    "$mutation_device_image" \
    "$mutation_work_directory"
)"

assert_equal \
  A \
  "$(
    printf '%s\n' "$mutation_selected_output" |
      awk -F= '$1 == "selected_copy" { print $2 }'
  )" \
  "select newly written metadata copy"

assert_equal \
  00000000000000000003 \
  "$(
    printf '%s\n' "$mutation_selected_output" |
      awk -F= '$1 == "generation" { print $2 }'
  )" \
  "verify newly written generation"

assert_equal \
  002 \
  "$(
    printf '%s\n' "$mutation_selected_output" |
      awk -F= '$1 == "pending_attempts" { print $2 }'
  )" \
  "verify newly written pending attempts"

printf X |
  dd \
    of="$mutation_device_image" \
    bs=512 \
    seek=2032 \
    count=1 \
    conv=notrunc \
    2>/dev/null

mutation_fallback_output="$(
  "$metadata_script" \
    select-device \
    "$mutation_device_image" \
    "$mutation_work_directory"
)"

assert_equal \
  B \
  "$(
    printf '%s\n' "$mutation_fallback_output" |
      awk -F= '$1 == "selected_copy" { print $2 }'
  )" \
  "fall back after corrupt metadata mutation"

assert_equal \
  00000000000000000002 \
  "$(
    printf '%s\n' "$mutation_fallback_output" |
      awk -F= '$1 == "generation" { print $2 }'
  )" \
  "preserve fallback metadata generation"

assert_equal \
  001 \
  "$(
    printf '%s\n' "$mutation_fallback_output" |
      awk -F= '$1 == "pending_attempts" { print $2 }'
  )" \
  "preserve fallback pending attempts"

no_pending_image="$test_root/no-pending-device.bin"
no_pending_work_directory="$test_root/no-pending-work"

dd \
  if=/dev/zero \
  of="$no_pending_image" \
  bs=512 \
  count=2048 \
  2>/dev/null

dd \
  if="$record_a" \
  of="$no_pending_image" \
  bs=512 \
  seek=2032 \
  count=8 \
  conv=notrunc \
  2>/dev/null

dd \
  if="$record_a" \
  of="$no_pending_image" \
  bs=512 \
  seek=2040 \
  count=8 \
  conv=notrunc \
  2>/dev/null

no_pending_sha256_before="$(
  sha256sum "$no_pending_image" |
    awk '{print $1}'
)"

if "$metadata_script" \
  prepare-pending-image \
  "$no_pending_image" \
  "$no_pending_work_directory" \
  >/dev/null \
  2>&1
then
  echo "error: mutated metadata without a pending slot" >&2
  exit 1
else
  echo "ok: reject metadata mutation without pending slot"
fi

no_pending_sha256_after="$(
  sha256sum "$no_pending_image" |
    awk '{print $1}'
)"

assert_equal \
  "$no_pending_sha256_before" \
  "$no_pending_sha256_after" \
  "preserve image without pending slot"

if "$metadata_script" \
  prepare-pending-image \
  /dev/null \
  "$test_root/non-regular-work" \
  >/dev/null \
  2>&1
then
  echo "error: accepted a non-regular metadata image" >&2
  exit 1
else
  echo "ok: reject non-regular metadata image"
fi

if "$metadata_script" \
  record-pending-attempt-device \
  "$mutation_device_image" \
  "$test_root/non-device-work" \
  >/dev/null \
  2>&1
then
  echo "error: accepted a regular file as a live metadata device" >&2
  exit 1
else
  echo "ok: reject regular file as live metadata device"
fi

overflow_record="$test_root/generation-overflow.bin"
overflow_image="$test_root/generation-overflow-device.bin"
overflow_work_directory="$test_root/generation-overflow-work"
overflow_error="$test_root/generation-overflow.err"

"$metadata_script" write \
  "$overflow_record" \
  99999999999999999999 \
  A B 001 003 \
  valid "$slot_a_uuid" "$slot_a_sha" \
  valid "$slot_b_uuid" "$slot_b_sha"

dd \
  if=/dev/zero \
  of="$overflow_image" \
  bs=512 \
  count=2048 \
  2>/dev/null

dd \
  if="$overflow_record" \
  of="$overflow_image" \
  bs=512 \
  seek=2032 \
  count=8 \
  conv=notrunc \
  2>/dev/null

dd \
  if="$overflow_record" \
  of="$overflow_image" \
  bs=512 \
  seek=2040 \
  count=8 \
  conv=notrunc \
  2>/dev/null

overflow_sha256_before="$(
  sha256sum "$overflow_image" |
    awk '{print $1}'
)"

if "$metadata_script" \
  prepare-pending-image \
  "$overflow_image" \
  "$overflow_work_directory" \
  >/dev/null \
  2>"$overflow_error"
then
  echo "error: accepted metadata generation overflow" >&2
  exit 1
fi

if grep -q 'generation_overflow' "$overflow_error"; then
  echo "ok: reject metadata generation overflow"
else
  echo "error: generation overflow was not reported" >&2
  cat "$overflow_error" >&2
  exit 1
fi

overflow_sha256_after="$(
  sha256sum "$overflow_image" |
    awk '{print $1}'
)"

assert_equal \
  "$overflow_sha256_before" \
  "$overflow_sha256_after" \
  "preserve image after generation overflow"

echo "ok: fake-image metadata mutation"

confirmation_image="$test_root/confirmation-device.bin"
confirmation_work_directory="$test_root/confirmation-work"

dd \
  if=/dev/zero \
  of="$confirmation_image" \
  bs=512 \
  count=2048 \
  2>/dev/null

dd \
  if="$record_a" \
  of="$confirmation_image" \
  bs=512 \
  seek=2032 \
  count=8 \
  conv=notrunc \
  2>/dev/null

dd \
  if="$record_b" \
  of="$confirmation_image" \
  bs=512 \
  seek=2040 \
  count=8 \
  conv=notrunc \
  2>/dev/null

"$metadata_script" \
  prepare-pending-image \
  "$confirmation_image" \
  "$confirmation_work_directory" \
  >/dev/null

previous_confirmation_copy="$test_root/confirmation-previous.bin"
previous_confirmation_copy_after="$test_root/confirmation-previous-after.bin"

dd \
  if="$confirmation_image" \
  of="$previous_confirmation_copy" \
  bs=512 \
  skip=2032 \
  count=8 \
  2>/dev/null

previous_confirmation_sha256="$(
  sha256sum "$previous_confirmation_copy" |
    awk '{print $1}'
)"

confirmation_output="$(
  "$metadata_script" \
    confirm-pending-image \
    "$confirmation_image" \
    B \
    "$confirmation_work_directory"
)"

assert_equal \
  A \
  "$(
    printf '%s\n' "$confirmation_output" |
      awk -F= '$1 == "previous_copy" { print $2 }'
  )" \
  "identify metadata copy before confirmation"

assert_equal \
  B \
  "$(
    printf '%s\n' "$confirmation_output" |
      awk -F= '$1 == "written_copy" { print $2 }'
  )" \
  "write confirmation to inactive metadata copy"

assert_equal \
  00000000000000000004 \
  "$(
    printf '%s\n' "$confirmation_output" |
      awk -F= '$1 == "generation" { print $2 }'
  )" \
  "increment confirmation generation"

assert_equal \
  B \
  "$(
    printf '%s\n' "$confirmation_output" |
      awk -F= '$1 == "confirmed_slot" { print $2 }'
  )" \
  "promote pending slot to confirmed"

assert_equal \
  - \
  "$(
    printf '%s\n' "$confirmation_output" |
      awk -F= '$1 == "pending_slot" { print $2 }'
  )" \
  "clear pending slot after confirmation"

assert_equal \
  000 \
  "$(
    printf '%s\n' "$confirmation_output" |
      awk -F= '$1 == "pending_attempts" { print $2 }'
  )" \
  "reset pending attempts after confirmation"

dd \
  if="$confirmation_image" \
  of="$previous_confirmation_copy_after" \
  bs=512 \
  skip=2032 \
  count=8 \
  2>/dev/null

previous_confirmation_sha256_after="$(
  sha256sum "$previous_confirmation_copy_after" |
    awk '{print $1}'
)"

assert_equal \
  "$previous_confirmation_sha256" \
  "$previous_confirmation_sha256_after" \
  "preserve previous metadata during confirmation"

confirmed_selection_output="$(
  "$metadata_script" \
    select-device \
    "$confirmation_image" \
    "$confirmation_work_directory"
)"

assert_equal \
  B \
  "$(
    printf '%s\n' "$confirmed_selection_output" |
      awk -F= '$1 == "selected_copy" { print $2 }'
  )" \
  "select confirmed metadata copy"

assert_equal \
  B \
  "$(
    printf '%s\n' "$confirmed_selection_output" |
      awk -F= '$1 == "selected_slot" { print $2 }'
  )" \
  "select newly confirmed slot"

assert_equal \
  confirmed \
  "$(
    printf '%s\n' "$confirmed_selection_output" |
      awk -F= '$1 == "selection_reason" { print $2 }'
  )" \
  "report confirmed policy after validation"

printf X |
  dd \
    of="$confirmation_image" \
    bs=512 \
    seek=2040 \
    count=1 \
    conv=notrunc \
    2>/dev/null

confirmation_fallback_output="$(
  "$metadata_script" \
    select-device \
    "$confirmation_image" \
    "$confirmation_work_directory"
)"

assert_equal \
  A \
  "$(
    printf '%s\n' "$confirmation_fallback_output" |
      awk -F= '$1 == "selected_copy" { print $2 }'
  )" \
  "fall back after corrupt confirmation record"

assert_equal \
  B \
  "$(
    printf '%s\n' "$confirmation_fallback_output" |
      awk -F= '$1 == "pending_slot" { print $2 }'
  )" \
  "preserve pending state after failed confirmation write"

wrong_slot_image="$test_root/wrong-confirmation-slot-device.bin"
wrong_slot_work_directory="$test_root/wrong-confirmation-slot-work"

dd \
  if=/dev/zero \
  of="$wrong_slot_image" \
  bs=512 \
  count=2048 \
  2>/dev/null

dd \
  if="$record_a" \
  of="$wrong_slot_image" \
  bs=512 \
  seek=2032 \
  count=8 \
  conv=notrunc \
  2>/dev/null

dd \
  if="$record_b" \
  of="$wrong_slot_image" \
  bs=512 \
  seek=2040 \
  count=8 \
  conv=notrunc \
  2>/dev/null

wrong_slot_sha256_before="$(
  sha256sum "$wrong_slot_image" |
    awk '{print $1}'
)"

if "$metadata_script" \
  confirm-pending-image \
  "$wrong_slot_image" \
  A \
  "$wrong_slot_work_directory" \
  >/dev/null \
  2>&1
then
  echo "error: confirmed a slot that was not pending" >&2
  exit 1
else
  echo "ok: reject confirmation of non-pending slot"
fi

wrong_slot_sha256_after="$(
  sha256sum "$wrong_slot_image" |
    awk '{print $1}'
)"

assert_equal \
  "$wrong_slot_sha256_before" \
  "$wrong_slot_sha256_after" \
  "preserve image after wrong-slot confirmation"

no_pending_confirmation_sha256_before="$(
  sha256sum "$no_pending_image" |
    awk '{print $1}'
)"

if "$metadata_script" \
  confirm-pending-image \
  "$no_pending_image" \
  B \
  "$test_root/no-pending-confirmation-work" \
  >/dev/null \
  2>&1
then
  echo "error: confirmed metadata without a pending slot" >&2
  exit 1
else
  echo "ok: reject confirmation without pending slot"
fi

no_pending_confirmation_sha256_after="$(
  sha256sum "$no_pending_image" |
    awk '{print $1}'
)"

assert_equal \
  "$no_pending_confirmation_sha256_before" \
  "$no_pending_confirmation_sha256_after" \
  "preserve image after missing-pending confirmation"

if "$metadata_script" \
  confirm-pending-image \
  /dev/null \
  B \
  "$test_root/non-regular-confirmation-work" \
  >/dev/null \
  2>&1
then
  echo "error: confirmed metadata on a non-regular image" >&2
  exit 1
else
  echo "ok: reject confirmation on non-regular image"
fi

confirmation_overflow_sha256_before="$(
  sha256sum "$overflow_image" |
    awk '{print $1}'
)"

if "$metadata_script" \
  confirm-pending-image \
  "$overflow_image" \
  B \
  "$test_root/confirmation-overflow-work" \
  >/dev/null \
  2>"$test_root/confirmation-overflow.err"
then
  echo "error: accepted confirmation generation overflow" >&2
  exit 1
fi

if grep -q 'generation_overflow' \
  "$test_root/confirmation-overflow.err"
then
  echo "ok: reject confirmation generation overflow"
else
  echo "error: confirmation overflow was not reported" >&2
  cat "$test_root/confirmation-overflow.err" >&2
  exit 1
fi

confirmation_overflow_sha256_after="$(
  sha256sum "$overflow_image" |
    awk '{print $1}'
)"

assert_equal \
  "$confirmation_overflow_sha256_before" \
  "$confirmation_overflow_sha256_after" \
  "preserve image after confirmation overflow"

echo "ok: fake-image pending confirmation"

write_metadata_test_image() {
  image_path="$1"
  record_a_path="$2"
  record_b_path="$3"

  dd \
    if=/dev/zero \
    of="$image_path" \
    bs=512 \
    count=2048 \
    2>/dev/null

  dd \
    if="$record_a_path" \
    of="$image_path" \
    bs=512 \
    seek=2032 \
    count=8 \
    conv=notrunc \
    2>/dev/null

  dd \
    if="$record_b_path" \
    of="$image_path" \
    bs=512 \
    seek=2040 \
    count=8 \
    conv=notrunc \
    2>/dev/null
}

extract_metadata_test_copy() {
  image_path="$1"
  copy_name="$2"
  output_path="$3"

  case "$copy_name" in
    A)
      record_sector=2032
      ;;
    B)
      record_sector=2040
      ;;
    *)
      echo "error: invalid test metadata copy: $copy_name" >&2
      exit 1
      ;;
  esac

  dd \
    if="$image_path" \
    of="$output_path" \
    bs=512 \
    skip="$record_sector" \
    count=8 \
    2>/dev/null
}

revert_record="$test_root/revert-confirmed.bin"
revert_image="$test_root/revert-device.bin"
revert_work_directory="$test_root/revert-work"

"$metadata_script" write \
  "$revert_record" \
  00000000000000000009 \
  B - 000 003 \
  valid "$slot_a_uuid" "$slot_a_sha" \
  valid "$slot_b_uuid" "$slot_b_sha"

write_metadata_test_image \
  "$revert_image" \
  "$revert_record" \
  "$revert_record"

revert_previous_copy="$test_root/revert-previous.bin"
revert_previous_copy_after="$test_root/revert-previous-after.bin"

extract_metadata_test_copy \
  "$revert_image" \
  A \
  "$revert_previous_copy"

revert_previous_sha256="$(
  sha256sum "$revert_previous_copy" |
    awk '{print $1}'
)"

revert_output="$(
  "$metadata_script" \
    revert-image \
    "$revert_image" \
    B \
    "$revert_work_directory"
)"

assert_equal \
  A \
  "$(
    printf '%s\n' "$revert_output" |
      awk -F= '$1 == "previous_copy" { print $2 }'
  )" \
  "identify metadata copy before revert"

assert_equal \
  B \
  "$(
    printf '%s\n' "$revert_output" |
      awk -F= '$1 == "written_copy" { print $2 }'
  )" \
  "write revert to inactive metadata copy"

assert_equal \
  00000000000000000010 \
  "$(
    printf '%s\n' "$revert_output" |
      awk -F= '$1 == "generation" { print $2 }'
  )" \
  "increment revert generation"

assert_equal \
  B \
  "$(
    printf '%s\n' "$revert_output" |
      awk -F= '$1 == "confirmed_slot" { print $2 }'
  )" \
  "preserve confirmed slot during revert"

assert_equal \
  A \
  "$(
    printf '%s\n' "$revert_output" |
      awk -F= '$1 == "pending_slot" { print $2 }'
  )" \
  "record previous slot as pending revert"

assert_equal \
  000 \
  "$(
    printf '%s\n' "$revert_output" |
      awk -F= '$1 == "pending_attempts" { print $2 }'
  )" \
  "reset revert pending attempts"

assert_equal \
  A \
  "$(
    printf '%s\n' "$revert_output" |
      awk -F= '$1 == "selected_slot" { print $2 }'
  )" \
  "select pending revert slot"

assert_equal \
  pending \
  "$(
    printf '%s\n' "$revert_output" |
      awk -F= '$1 == "selection_reason" { print $2 }'
  )" \
  "report pending revert reason"

extract_metadata_test_copy \
  "$revert_image" \
  A \
  "$revert_previous_copy_after"

revert_previous_sha256_after="$(
  sha256sum "$revert_previous_copy_after" |
    awk '{print $1}'
)"

assert_equal \
  "$revert_previous_sha256" \
  "$revert_previous_sha256_after" \
  "preserve previous metadata during revert"

revert_selection_output="$(
  "$metadata_script" \
    select-device \
    "$revert_image" \
    "$revert_work_directory"
)"

assert_equal \
  B \
  "$(
    printf '%s\n' "$revert_selection_output" |
      awk -F= '$1 == "selected_copy" { print $2 }'
  )" \
  "select manual revert metadata copy"

assert_equal \
  A \
  "$(
    printf '%s\n' "$revert_selection_output" |
      awk -F= '$1 == "selected_slot" { print $2 }'
  )" \
  "choose manual revert slot"

assert_equal \
  pending \
  "$(
    printf '%s\n' "$revert_selection_output" |
      awk -F= '$1 == "selection_reason" { print $2 }'
  )" \
  "apply pending policy to manual revert"

printf X |
  dd \
    of="$revert_image" \
    bs=512 \
    seek=2040 \
    count=1 \
    conv=notrunc \
    2>/dev/null

revert_fallback_output="$(
  "$metadata_script" \
    select-device \
    "$revert_image" \
    "$revert_work_directory"
)"

assert_equal \
  A \
  "$(
    printf '%s\n' "$revert_fallback_output" |
      awk -F= '$1 == "selected_copy" { print $2 }'
  )" \
  "fall back after corrupt revert record"

assert_equal \
  B \
  "$(
    printf '%s\n' "$revert_fallback_output" |
      awk -F= '$1 == "selected_slot" { print $2 }'
  )" \
  "retain confirmed slot after failed revert write"

pending_revert_image="$test_root/pending-revert-device.bin"

write_metadata_test_image \
  "$pending_revert_image" \
  "$record_b" \
  "$record_b"

pending_revert_sha256_before="$(
  sha256sum "$pending_revert_image" |
    awk '{print $1}'
)"

if "$metadata_script" \
  revert-image \
  "$pending_revert_image" \
  A \
  "$test_root/pending-revert-work" \
  >/dev/null \
  2>&1
then
  echo "error: accepted revert while a slot was pending" >&2
  exit 1
else
  echo "ok: reject revert while a slot is pending"
fi

pending_revert_sha256_after="$(
  sha256sum "$pending_revert_image" |
    awk '{print $1}'
)"

assert_equal \
  "$pending_revert_sha256_before" \
  "$pending_revert_sha256_after" \
  "preserve image after pending revert rejection"

empty_revert_image="$test_root/empty-revert-device.bin"

write_metadata_test_image \
  "$empty_revert_image" \
  "$record_a" \
  "$record_a"

empty_revert_sha256_before="$(
  sha256sum "$empty_revert_image" |
    awk '{print $1}'
)"

if "$metadata_script" \
  revert-image \
  "$empty_revert_image" \
  A \
  "$test_root/empty-revert-work" \
  >/dev/null \
  2>&1
then
  echo "error: reverted to an empty slot" >&2
  exit 1
else
  echo "ok: reject revert to empty slot"
fi

empty_revert_sha256_after="$(
  sha256sum "$empty_revert_image" |
    awk '{print $1}'
)"

assert_equal \
  "$empty_revert_sha256_before" \
  "$empty_revert_sha256_after" \
  "preserve image after empty-slot revert rejection"

bad_revert_record="$test_root/bad-revert-record.bin"
bad_revert_image="$test_root/bad-revert-device.bin"

"$metadata_script" write \
  "$bad_revert_record" \
  00000000000000000011 \
  A - 000 003 \
  valid "$slot_a_uuid" "$slot_a_sha" \
  bad "$slot_b_uuid" "$slot_b_sha"

write_metadata_test_image \
  "$bad_revert_image" \
  "$bad_revert_record" \
  "$bad_revert_record"

bad_revert_sha256_before="$(
  sha256sum "$bad_revert_image" |
    awk '{print $1}'
)"

if "$metadata_script" \
  revert-image \
  "$bad_revert_image" \
  A \
  "$test_root/bad-revert-work" \
  >/dev/null \
  2>&1
then
  echo "error: reverted to a bad slot" >&2
  exit 1
else
  echo "ok: reject revert to bad slot"
fi

bad_revert_sha256_after="$(
  sha256sum "$bad_revert_image" |
    awk '{print $1}'
)"

assert_equal \
  "$bad_revert_sha256_before" \
  "$bad_revert_sha256_after" \
  "preserve image after bad-slot revert rejection"

active_mismatch_image="$test_root/revert-active-mismatch-device.bin"

write_metadata_test_image \
  "$active_mismatch_image" \
  "$revert_record" \
  "$revert_record"

active_mismatch_sha256_before="$(
  sha256sum "$active_mismatch_image" |
    awk '{print $1}'
)"

if "$metadata_script" \
  revert-image \
  "$active_mismatch_image" \
  A \
  "$test_root/revert-active-mismatch-work" \
  >/dev/null \
  2>&1
then
  echo "error: reverted from a non-confirmed active slot" >&2
  exit 1
else
  echo "ok: reject revert from non-confirmed active slot"
fi

active_mismatch_sha256_after="$(
  sha256sum "$active_mismatch_image" |
    awk '{print $1}'
)"

assert_equal \
  "$active_mismatch_sha256_before" \
  "$active_mismatch_sha256_after" \
  "preserve image after active-slot mismatch"

if "$metadata_script" \
  revert-image \
  /dev/null \
  B \
  "$test_root/non-regular-revert-work" \
  >/dev/null \
  2>&1
then
  echo "error: reverted metadata on a non-regular image" >&2
  exit 1
else
  echo "ok: reject revert on non-regular image"
fi

revert_overflow_record="$test_root/revert-overflow-record.bin"
revert_overflow_image="$test_root/revert-overflow-device.bin"
revert_overflow_error="$test_root/revert-overflow.err"

"$metadata_script" write \
  "$revert_overflow_record" \
  99999999999999999999 \
  B - 000 003 \
  valid "$slot_a_uuid" "$slot_a_sha" \
  valid "$slot_b_uuid" "$slot_b_sha"

write_metadata_test_image \
  "$revert_overflow_image" \
  "$revert_overflow_record" \
  "$revert_overflow_record"

revert_overflow_sha256_before="$(
  sha256sum "$revert_overflow_image" |
    awk '{print $1}'
)"

if "$metadata_script" \
  revert-image \
  "$revert_overflow_image" \
  B \
  "$test_root/revert-overflow-work" \
  >/dev/null \
  2>"$revert_overflow_error"
then
  echo "error: accepted revert generation overflow" >&2
  exit 1
fi

if grep -q 'generation_overflow' "$revert_overflow_error"; then
  echo "ok: reject revert generation overflow"
else
  echo "error: revert overflow was not reported" >&2
  cat "$revert_overflow_error" >&2
  exit 1
fi

revert_overflow_sha256_after="$(
  sha256sum "$revert_overflow_image" |
    awk '{print $1}'
)"

assert_equal \
  "$revert_overflow_sha256_before" \
  "$revert_overflow_sha256_after" \
  "preserve image after revert overflow"

echo "ok: fake-image manual revert"

prevent_revert_record="$test_root/prevent-revert-record.bin"
prevent_revert_image="$test_root/prevent-revert-device.bin"
prevent_revert_work_directory="$test_root/prevent-revert-work"

"$metadata_script" write \
  "$prevent_revert_record" \
  00000000000000000012 \
  B - 000 003 \
  valid "$slot_a_uuid" "$slot_a_sha" \
  valid "$slot_b_uuid" "$slot_b_sha"

write_metadata_test_image \
  "$prevent_revert_image" \
  "$prevent_revert_record" \
  "$prevent_revert_record"

prevent_revert_previous_copy="$test_root/prevent-revert-previous.bin"
prevent_revert_previous_copy_after="$test_root/prevent-revert-previous-after.bin"

extract_metadata_test_copy \
  "$prevent_revert_image" \
  A \
  "$prevent_revert_previous_copy"

prevent_revert_previous_sha256="$(
  sha256sum "$prevent_revert_previous_copy" |
    awk '{print $1}'
)"

prevent_revert_output="$(
  "$metadata_script" \
    prevent-revert-image \
    "$prevent_revert_image" \
    B \
    "$prevent_revert_work_directory"
)"

assert_equal \
  A \
  "$(
    printf '%s\n' "$prevent_revert_output" |
      awk -F= '$1 == "previous_copy" { print $2 }'
  )" \
  "identify metadata copy before prevent-revert"

assert_equal \
  B \
  "$(
    printf '%s\n' "$prevent_revert_output" |
      awk -F= '$1 == "written_copy" { print $2 }'
  )" \
  "write prevent-revert to inactive metadata copy"

assert_equal \
  00000000000000000013 \
  "$(
    printf '%s\n' "$prevent_revert_output" |
      awk -F= '$1 == "generation" { print $2 }'
  )" \
  "increment prevent-revert generation"

assert_equal \
  B \
  "$(
    printf '%s\n' "$prevent_revert_output" |
      awk -F= '$1 == "confirmed_slot" { print $2 }'
  )" \
  "preserve confirmed slot during prevent-revert"

assert_equal \
  - \
  "$(
    printf '%s\n' "$prevent_revert_output" |
      awk -F= '$1 == "pending_slot" { print $2 }'
  )" \
  "keep pending slot clear during prevent-revert"

assert_equal \
  empty \
  "$(
    printf '%s\n' "$prevent_revert_output" |
      awk -F= '$1 == "slot_a_status" { print $2 }'
  )" \
  "mark rollback slot reusable"

assert_equal \
  - \
  "$(
    printf '%s\n' "$prevent_revert_output" |
      awk -F= '$1 == "slot_a_firmware_id" { print $2 }'
  )" \
  "clear reusable slot firmware ID"

assert_equal \
  - \
  "$(
    printf '%s\n' "$prevent_revert_output" |
      awk -F= '$1 == "slot_a_sha256" { print $2 }'
  )" \
  "clear reusable slot checksum"

assert_equal \
  valid \
  "$(
    printf '%s\n' "$prevent_revert_output" |
      awk -F= '$1 == "slot_b_status" { print $2 }'
  )" \
  "preserve running slot status"

assert_equal \
  "$slot_b_uuid" \
  "$(
    printf '%s\n' "$prevent_revert_output" |
      awk -F= '$1 == "slot_b_firmware_id" { print $2 }'
  )" \
  "preserve running slot firmware ID"

assert_equal \
  "$slot_b_sha" \
  "$(
    printf '%s\n' "$prevent_revert_output" |
      awk -F= '$1 == "slot_b_sha256" { print $2 }'
  )" \
  "preserve running slot checksum"

assert_equal \
  B \
  "$(
    printf '%s\n' "$prevent_revert_output" |
      awk -F= '$1 == "selected_slot" { print $2 }'
  )" \
  "retain running slot after prevent-revert"

assert_equal \
  confirmed \
  "$(
    printf '%s\n' "$prevent_revert_output" |
      awk -F= '$1 == "selection_reason" { print $2 }'
  )" \
  "retain confirmed policy after prevent-revert"

extract_metadata_test_copy \
  "$prevent_revert_image" \
  A \
  "$prevent_revert_previous_copy_after"

prevent_revert_previous_sha256_after="$(
  sha256sum "$prevent_revert_previous_copy_after" |
    awk '{print $1}'
)"

assert_equal \
  "$prevent_revert_previous_sha256" \
  "$prevent_revert_previous_sha256_after" \
  "preserve previous metadata during prevent-revert"

prevent_revert_selection_output="$(
  "$metadata_script" \
    select-device \
    "$prevent_revert_image" \
    "$prevent_revert_work_directory"
)"

assert_equal \
  B \
  "$(
    printf '%s\n' "$prevent_revert_selection_output" |
      awk -F= '$1 == "selected_copy" { print $2 }'
  )" \
  "select prevent-revert metadata copy"

assert_equal \
  B \
  "$(
    printf '%s\n' "$prevent_revert_selection_output" |
      awk -F= '$1 == "selected_slot" { print $2 }'
  )" \
  "select confirmed slot after prevent-revert"

printf X |
  dd \
    of="$prevent_revert_image" \
    bs=512 \
    seek=2040 \
    count=1 \
    conv=notrunc \
    2>/dev/null

prevent_revert_fallback_output="$(
  "$metadata_script" \
    select-device \
    "$prevent_revert_image" \
    "$prevent_revert_work_directory"
)"

assert_equal \
  A \
  "$(
    printf '%s\n' "$prevent_revert_fallback_output" |
      awk -F= '$1 == "selected_copy" { print $2 }'
  )" \
  "fall back after corrupt prevent-revert record"

assert_equal \
  valid \
  "$(
    printf '%s\n' "$prevent_revert_fallback_output" |
      awk -F= '$1 == "slot_a_status" { print $2 }'
  )" \
  "retain rollback eligibility after failed prevent-revert write"

pending_prevent_revert_image="$test_root/pending-prevent-revert-device.bin"

write_metadata_test_image \
  "$pending_prevent_revert_image" \
  "$record_b" \
  "$record_b"

pending_prevent_revert_sha256_before="$(
  sha256sum "$pending_prevent_revert_image" |
    awk '{print $1}'
)"

if "$metadata_script" \
  prevent-revert-image \
  "$pending_prevent_revert_image" \
  A \
  "$test_root/pending-prevent-revert-work" \
  >/dev/null \
  2>&1
then
  echo "error: accepted prevent-revert while a slot was pending" >&2
  exit 1
else
  echo "ok: reject prevent-revert while a slot is pending"
fi

pending_prevent_revert_sha256_after="$(
  sha256sum "$pending_prevent_revert_image" |
    awk '{print $1}'
)"

assert_equal \
  "$pending_prevent_revert_sha256_before" \
  "$pending_prevent_revert_sha256_after" \
  "preserve image after pending prevent-revert rejection"

empty_prevent_revert_image="$test_root/empty-prevent-revert-device.bin"

write_metadata_test_image \
  "$empty_prevent_revert_image" \
  "$record_a" \
  "$record_a"

empty_prevent_revert_sha256_before="$(
  sha256sum "$empty_prevent_revert_image" |
    awk '{print $1}'
)"

if "$metadata_script" \
  prevent-revert-image \
  "$empty_prevent_revert_image" \
  A \
  "$test_root/empty-prevent-revert-work" \
  >/dev/null \
  2>&1
then
  echo "error: accepted prevent-revert without a valid rollback slot" >&2
  exit 1
else
  echo "ok: reject prevent-revert without valid rollback slot"
fi

empty_prevent_revert_sha256_after="$(
  sha256sum "$empty_prevent_revert_image" |
    awk '{print $1}'
)"

assert_equal \
  "$empty_prevent_revert_sha256_before" \
  "$empty_prevent_revert_sha256_after" \
  "preserve image without valid rollback slot"

bad_prevent_revert_image="$test_root/bad-prevent-revert-device.bin"

write_metadata_test_image \
  "$bad_prevent_revert_image" \
  "$bad_revert_record" \
  "$bad_revert_record"

bad_prevent_revert_sha256_before="$(
  sha256sum "$bad_prevent_revert_image" |
    awk '{print $1}'
)"

if "$metadata_script" \
  prevent-revert-image \
  "$bad_prevent_revert_image" \
  A \
  "$test_root/bad-prevent-revert-work" \
  >/dev/null \
  2>&1
then
  echo "error: accepted prevent-revert with a bad rollback slot" >&2
  exit 1
else
  echo "ok: reject prevent-revert with bad rollback slot"
fi

bad_prevent_revert_sha256_after="$(
  sha256sum "$bad_prevent_revert_image" |
    awk '{print $1}'
)"

assert_equal \
  "$bad_prevent_revert_sha256_before" \
  "$bad_prevent_revert_sha256_after" \
  "preserve image with bad rollback slot"

prevent_revert_active_mismatch_image="$test_root/prevent-revert-active-mismatch.bin"

write_metadata_test_image \
  "$prevent_revert_active_mismatch_image" \
  "$prevent_revert_record" \
  "$prevent_revert_record"

prevent_revert_active_mismatch_sha256_before="$(
  sha256sum "$prevent_revert_active_mismatch_image" |
    awk '{print $1}'
)"

if "$metadata_script" \
  prevent-revert-image \
  "$prevent_revert_active_mismatch_image" \
  A \
  "$test_root/prevent-revert-active-mismatch-work" \
  >/dev/null \
  2>&1
then
  echo "error: prevented revert from a non-confirmed slot" >&2
  exit 1
else
  echo "ok: reject prevent-revert from non-confirmed active slot"
fi

prevent_revert_active_mismatch_sha256_after="$(
  sha256sum "$prevent_revert_active_mismatch_image" |
    awk '{print $1}'
)"

assert_equal \
  "$prevent_revert_active_mismatch_sha256_before" \
  "$prevent_revert_active_mismatch_sha256_after" \
  "preserve image after prevent-revert active mismatch"

if "$metadata_script" \
  prevent-revert-image \
  /dev/null \
  B \
  "$test_root/non-regular-prevent-revert-work" \
  >/dev/null \
  2>&1
then
  echo "error: prevented revert on a non-regular image" >&2
  exit 1
else
  echo "ok: reject prevent-revert on non-regular image"
fi

prevent_revert_overflow_record="$test_root/prevent-revert-overflow-record.bin"
prevent_revert_overflow_image="$test_root/prevent-revert-overflow-device.bin"
prevent_revert_overflow_error="$test_root/prevent-revert-overflow.err"

"$metadata_script" write \
  "$prevent_revert_overflow_record" \
  99999999999999999999 \
  B - 000 003 \
  valid "$slot_a_uuid" "$slot_a_sha" \
  valid "$slot_b_uuid" "$slot_b_sha"

write_metadata_test_image \
  "$prevent_revert_overflow_image" \
  "$prevent_revert_overflow_record" \
  "$prevent_revert_overflow_record"

prevent_revert_overflow_sha256_before="$(
  sha256sum "$prevent_revert_overflow_image" |
    awk '{print $1}'
)"

if "$metadata_script" \
  prevent-revert-image \
  "$prevent_revert_overflow_image" \
  B \
  "$test_root/prevent-revert-overflow-work" \
  >/dev/null \
  2>"$prevent_revert_overflow_error"
then
  echo "error: accepted prevent-revert generation overflow" >&2
  exit 1
fi

if grep -q 'generation_overflow' "$prevent_revert_overflow_error"; then
  echo "ok: reject prevent-revert generation overflow"
else
  echo "error: prevent-revert overflow was not reported" >&2
  cat "$prevent_revert_overflow_error" >&2
  exit 1
fi

prevent_revert_overflow_sha256_after="$(
  sha256sum "$prevent_revert_overflow_image" |
    awk '{print $1}'
)"

assert_equal \
  "$prevent_revert_overflow_sha256_before" \
  "$prevent_revert_overflow_sha256_after" \
  "preserve image after prevent-revert overflow"

echo "ok: fake-image prevent-revert"
echo "ok: rollback metadata tests"
