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

echo "ok: rollback metadata tests"
