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
echo "ok: rollback metadata tests"
