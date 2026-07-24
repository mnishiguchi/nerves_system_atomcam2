#!/bin/sh
set -eu

PATH=/sbin:/bin:/usr/sbin:/usr/bin
export PATH

metadata_magic="ATOMCAM2_BOOT_METADATA_V1"
metadata_record_size=4096
metadata_sector_size=512
metadata_record_sector_count=8
metadata_record_a_sector=2032
metadata_record_b_sector=2040
metadata_boot_partition_sector=2048
metadata_error=""
metadata_selected_record=""
metadata_selected_slot=""
metadata_selection_reason=""
metadata_previous_copy=""
metadata_written_copy=""
metadata_incremented_value=""

validate_values() {
  if awk \
    -v generation="$metadata_generation" \
    -v confirmed="$metadata_confirmed_slot" \
    -v pending="$metadata_pending_slot" \
    -v attempts="$metadata_pending_attempts" \
    -v maximum="$metadata_max_attempts" \
    -v a_status="$metadata_slot_a_status" \
    -v a_id="$metadata_slot_a_firmware_id" \
    -v a_sha="$metadata_slot_a_sha256" \
    -v b_status="$metadata_slot_b_status" \
    -v b_id="$metadata_slot_b_firmware_id" \
    -v b_sha="$metadata_slot_b_sha256" '
    function decimal(value, width) {
      return length(value) == width && value !~ /[^0-9]/
    }

    function hexadecimal(value) {
      return value != "" && value !~ /[^0-9a-f]/
    }

    function firmware_id(value) {
      if (value == "-") {
        return 1
      }

      return length(value) == 36 &&
        substr(value, 9, 1) == "-" &&
        substr(value, 14, 1) == "-" &&
        substr(value, 19, 1) == "-" &&
        substr(value, 24, 1) == "-" &&
        hexadecimal(substr(value, 1, 8)) &&
        hexadecimal(substr(value, 10, 4)) &&
        hexadecimal(substr(value, 15, 4)) &&
        hexadecimal(substr(value, 20, 4)) &&
        hexadecimal(substr(value, 25, 12))
    }

    function sha256(value) {
      if (value == "-") {
        return 1
      }

      return length(value) == 64 && value !~ /[^0-9a-f]/
    }

    function slot(status, id, sha) {
      if (status == "empty") {
        return id == "-" && sha == "-"
      }

      if (status != "valid" && status != "bad") {
        return 0
      }

      return firmware_id(id) && sha256(sha)
    }

    BEGIN {
      if (!decimal(generation, 20)) exit 1
      if (confirmed != "A" && confirmed != "B") exit 1
      if (pending != "-" && pending != "A" && pending != "B") exit 1
      if (!decimal(attempts, 3)) exit 1
      if (!decimal(maximum, 3) || maximum == "000") exit 1
      if (pending == "-" && attempts != "000") exit 1
      if (pending != "-" && (attempts + 0) > (maximum + 0)) exit 1
      if (!slot(a_status, a_id, a_sha)) exit 1
      if (!slot(b_status, b_id, b_sha)) exit 1
      if (confirmed == "A" && a_status != "valid") exit 1
      if (confirmed == "B" && b_status != "valid") exit 1
      if (pending == "A" && a_status != "valid") exit 1
      if (pending == "B" && b_status != "valid") exit 1
    }
  '; then
    return 0
  else
    metadata_error="invalid_values"
    return 1
  fi
}

write_payload() {
  printf '%s\n' "$metadata_magic"
  printf 'generation=%s\n' "$metadata_generation"
  printf 'confirmed_slot=%s\n' "$metadata_confirmed_slot"
  printf 'pending_slot=%s\n' "$metadata_pending_slot"
  printf 'pending_attempts=%s\n' "$metadata_pending_attempts"
  printf 'max_attempts=%s\n' "$metadata_max_attempts"
  printf 'slot_a_status=%s\n' "$metadata_slot_a_status"
  printf 'slot_a_firmware_id=%s\n' "$metadata_slot_a_firmware_id"
  printf 'slot_a_sha256=%s\n' "$metadata_slot_a_sha256"
  printf 'slot_b_status=%s\n' "$metadata_slot_b_status"
  printf 'slot_b_firmware_id=%s\n' "$metadata_slot_b_firmware_id"
  printf 'slot_b_sha256=%s\n' "$metadata_slot_b_sha256"
}

metadata_write() {
  if [ "$#" -ne 12 ]; then
    metadata_error="write_argument_count"
    return 1
  fi

  output_path="$1"
  metadata_generation="$2"
  metadata_confirmed_slot="$3"
  metadata_pending_slot="$4"
  metadata_pending_attempts="$5"
  metadata_max_attempts="$6"
  metadata_slot_a_status="$7"
  metadata_slot_a_firmware_id="$8"
  metadata_slot_a_sha256="$9"
  shift 9
  metadata_slot_b_status="$1"
  metadata_slot_b_firmware_id="$2"
  metadata_slot_b_sha256="$3"
  metadata_error=""

  if ! validate_values; then
    return 1
  fi

  metadata_checksum="$(
    write_payload |
      sha256sum |
      awk '{print $1}'
  )"

  payload_path="${output_path}.payload.$$"
  temporary_path="${output_path}.tmp.$$"

  if ! {
    write_payload
    printf 'checksum_sha256=%s\n' "$metadata_checksum"
  } > "$payload_path"; then

    rm -f "$payload_path"
    metadata_error="payload_write_failed"
    return 1
  fi

  if ! printf '%4096s' '' > "$temporary_path"; then
    rm -f "$payload_path"
    metadata_error="record_allocation_failed"
    return 1
  fi

  if ! dd \
    if="$payload_path" \
    of="$temporary_path" \
    bs="$metadata_record_size" \
    count=1 \
    conv=notrunc \
    2>/dev/null; then

    rm -f "$payload_path" "$temporary_path"
    metadata_error="record_write_failed"
    return 1
  fi

  rm -f "$payload_path"

  if mv -f "$temporary_path" "$output_path"; then
    return 0
  else
    rm -f "$temporary_path"
    metadata_error="record_replace_failed"
    return 1
  fi
}

metadata_read() {
  record_path="$1"
  metadata_error=""

  if [ ! -f "$record_path" ]; then
    metadata_error="record_missing"
    return 1
  fi

  metadata_values="$(
    awk -v magic="$metadata_magic" '
      BEGIN {
        keys[2] = "generation"
        keys[3] = "confirmed_slot"
        keys[4] = "pending_slot"
        keys[5] = "pending_attempts"
        keys[6] = "max_attempts"
        keys[7] = "slot_a_status"
        keys[8] = "slot_a_firmware_id"
        keys[9] = "slot_a_sha256"
        keys[10] = "slot_b_status"
        keys[11] = "slot_b_firmware_id"
        keys[12] = "slot_b_sha256"
        keys[13] = "checksum_sha256"
      }

      NR == 1 {
        if ($0 != magic) exit 1
        next
      }

      NR >= 2 && NR <= 13 {
        prefix = keys[NR] "="

        if (index($0, prefix) != 1) {
          exit 1
        }

        values[NR] = substr($0, length(prefix) + 1)
        next
      }

      NR >= 14 && $0 !~ /^ *$/ {
        exit 1
      }

      END {
        if (NR < 13) {
          exit 1
        }

        for (line_number = 2; line_number <= 13; line_number++) {
          if (line_number > 2) {
            printf " "
          }

          printf "%s", values[line_number]
        }
      }
    ' "$record_path"
  )" || {
    metadata_error="record_invalid"
    return 1
  }

  set -- $metadata_values

  if [ "$#" -ne 12 ]; then
    metadata_error="record_invalid"
    return 1
  fi

  metadata_generation="$1"
  metadata_confirmed_slot="$2"
  metadata_pending_slot="$3"
  metadata_pending_attempts="$4"
  metadata_max_attempts="$5"
  metadata_slot_a_status="$6"
  metadata_slot_a_firmware_id="$7"
  metadata_slot_a_sha256="$8"
  metadata_slot_b_status="$9"
  shift 9
  metadata_slot_b_firmware_id="$1"
  metadata_slot_b_sha256="$2"
  metadata_checksum="$3"

  if ! validate_values; then
    return 1
  fi

  expected_checksum="$(
    write_payload |
      sha256sum |
      awk '{print $1}'
  )"

  if [ "$metadata_checksum" != "$expected_checksum" ]; then
    metadata_error="checksum_mismatch"
    return 1
  fi

  return 0
}

metadata_print() {
  write_payload
  printf 'checksum_sha256=%s\n' "$metadata_checksum"
}

use_selected_record() {
  selected_record="$1"

  if metadata_read "$selected_record"; then
    metadata_selected_record="$selected_record"
    metadata_error=""
    return 0
  else
    metadata_selected_record=""
    metadata_error="selected_record_invalid"
    return 1
  fi
}

metadata_select() {
  first_record="$1"
  second_record="$2"
  metadata_selected_record=""
  first_valid=0
  second_valid=0

  if metadata_read "$first_record"; then
    first_valid=1
    first_generation="$metadata_generation"
    first_checksum="$metadata_checksum"
  fi

  if metadata_read "$second_record"; then
    second_valid=1
    second_generation="$metadata_generation"
    second_checksum="$metadata_checksum"
  fi

  if [ "$first_valid" -eq 0 ]; then
    if [ "$second_valid" -eq 0 ]; then
      metadata_error="no_valid_record"
      return 1
    fi

    if use_selected_record "$second_record"; then
      return 0
    else
      return 1
    fi
  fi

  if [ "$second_valid" -eq 0 ]; then
    if use_selected_record "$first_record"; then
      return 0
    else
      return 1
    fi
  fi

  if [ "$first_generation" = "$second_generation" ]; then
    if [ "$first_checksum" = "$second_checksum" ]; then
      if use_selected_record "$first_record"; then
        return 0
      else
        return 1
      fi
    fi

    metadata_error="equal_generation_conflict"
    return 1
  fi

  if awk \
    -v first="g$first_generation" \
    -v second="g$second_generation" \
    'BEGIN { exit !(first > second) }'; then

    if use_selected_record "$first_record"; then
      return 0
    else
      return 1
    fi
  else
    if use_selected_record "$second_record"; then
      return 0
    else
      return 1
    fi
  fi
}


metadata_choose_loaded_slot() {
  metadata_selected_slot=""
  metadata_selection_reason=""
  metadata_error=""

  if [ "$metadata_pending_slot" = "-" ]; then
    metadata_selected_slot="$metadata_confirmed_slot"
    metadata_selection_reason="confirmed"
    return 0
  fi

  if awk \
    -v attempts="$metadata_pending_attempts" \
    -v maximum="$metadata_max_attempts" \
    'BEGIN { exit !((attempts + 0) < (maximum + 0)) }'
  then
    metadata_selected_slot="$metadata_pending_slot"
    metadata_selection_reason="pending"
  else
    metadata_selected_slot="$metadata_confirmed_slot"
    metadata_selection_reason="pending_attempt_limit"
  fi

  return 0
}

metadata_choose_slot() {
  if [ "$#" -ne 1 ]; then
    metadata_error="choose_slot_argument_count"
    return 1
  fi

  record_path="$1"

  if ! metadata_read "$record_path"; then
    return 1
  fi

  metadata_choose_loaded_slot
}

metadata_firmware_id_from_sha256() {
  if [ "$#" -ne 1 ]; then
    metadata_error="firmware_id_argument_count"
    return 1
  fi

  firmware_sha256="$1"

  firmware_id="$(
    awk -v sha256="$firmware_sha256" '
      BEGIN {
        if (length(sha256) != 64) {
          exit 1
        }

        if (sha256 ~ /[^0-9a-f]/) {
          exit 1
        }

        printf "%s-%s-5%s-8%s-%s\n",
          substr(sha256, 1, 8),
          substr(sha256, 9, 4),
          substr(sha256, 14, 3),
          substr(sha256, 18, 3),
          substr(sha256, 21, 12)
      }
    '
  )" || {
    metadata_error="invalid_firmware_sha256"
    return 1
  }

  printf '%s\n' "$firmware_id"
}

metadata_write_initial_record() {
  if [ "$#" -ne 2 ]; then
    metadata_error="initial_record_argument_count"
    return 1
  fi

  output_path="$1"
  rootfs_path="$2"

  if [ ! -f "$rootfs_path" ]; then
    metadata_error="rootfs_missing"
    return 1
  fi

  if [ ! -r "$rootfs_path" ]; then
    metadata_error="rootfs_not_readable"
    return 1
  fi

  slot_a_sha256="$(
    sha256sum "$rootfs_path" |
      awk '{print $1}'
  )" || {
    metadata_error="rootfs_checksum_failed"
    return 1
  }

  slot_a_firmware_id="$(
    metadata_firmware_id_from_sha256 "$slot_a_sha256"
  )" || {
    return 1
  }

  metadata_write \
    "$output_path" \
    00000000000000000001 \
    A \
    - \
    000 \
    003 \
    valid \
    "$slot_a_firmware_id" \
    "$slot_a_sha256" \
    empty \
    - \
    -
}

metadata_validate_device_layout() {
  record_a_end="$(
    awk \
      -v start="$metadata_record_a_sector" \
      -v count="$metadata_record_sector_count" \
      'BEGIN { print start + count }'
  )"

  record_b_end="$(
    awk \
      -v start="$metadata_record_b_sector" \
      -v count="$metadata_record_sector_count" \
      'BEGIN { print start + count }'
  )"

  if [ "$record_a_end" -ne "$metadata_record_b_sector" ]; then
    metadata_error="record_layout_not_contiguous"
    return 1
  elif [ "$record_b_end" -ne "$metadata_boot_partition_sector" ]; then
    metadata_error="record_layout_overlaps_boot_partition"
    return 1
  else
    return 0
  fi
}

metadata_extract_device_copy() {
  if [ "$#" -ne 3 ]; then
    metadata_error="extract_argument_count"
    return 1
  fi

  device_path="$1"
  copy_name="$2"
  output_path="$3"

  if ! metadata_validate_device_layout; then
    return 1
  fi

  case "$copy_name" in
    A)
      record_sector="$metadata_record_a_sector"
      ;;
    B)
      record_sector="$metadata_record_b_sector"
      ;;
    *)
      metadata_error="invalid_copy_name"
      return 1
      ;;
  esac

  if dd \
    if="$device_path" \
    of="$output_path" \
    bs="$metadata_sector_size" \
    skip="$record_sector" \
    count="$metadata_record_sector_count" \
    conv=sync \
    2>/dev/null; then

    return 0
  else
    metadata_error="device_record_read_failed"
    return 1
  fi
}

metadata_select_device() {
  if [ "$#" -ne 2 ]; then
    metadata_error="select_device_argument_count"
    return 1
  fi

  device_path="$1"
  work_directory="$2"
  metadata_selected_copy=""
  metadata_selected_record=""
  metadata_error=""

  if [ ! -r "$device_path" ]; then
    metadata_error="device_not_readable"
    return 1
  fi

  if ! mkdir -p "$work_directory"; then
    metadata_error="work_directory_failed"
    return 1
  fi

  device_record_a="$work_directory/atomcam2-boot-metadata-a.$$"
  device_record_b="$work_directory/atomcam2-boot-metadata-b.$$"

  if ! metadata_extract_device_copy \
    "$device_path" \
    A \
    "$device_record_a"; then

    rm -f "$device_record_a" "$device_record_b"
    return 1
  fi

  if ! metadata_extract_device_copy \
    "$device_path" \
    B \
    "$device_record_b"; then

    rm -f "$device_record_a" "$device_record_b"
    return 1
  fi

  if ! metadata_select "$device_record_a" "$device_record_b"; then
    rm -f "$device_record_a" "$device_record_b"
    return 1
  fi

  if [ "$metadata_selected_record" = "$device_record_a" ]; then
    metadata_selected_copy="A"
  elif [ "$metadata_selected_record" = "$device_record_b" ]; then
    metadata_selected_copy="B"
  else
    rm -f "$device_record_a" "$device_record_b"
    metadata_selected_record=""
    metadata_error="selected_record_unknown"
    return 1
  fi

  if ! metadata_choose_loaded_slot; then
    rm -f "$device_record_a" "$device_record_b"
    metadata_selected_record=""
    return 1
  fi

  rm -f "$device_record_a" "$device_record_b"
  metadata_selected_record=""
  metadata_error=""

  return 0
}

metadata_increment_decimal() {
  if [ "$#" -ne 3 ]; then
    metadata_error="increment_decimal_argument_count"
    return 1
  fi

  decimal_name="$1"
  decimal_value="$2"
  decimal_width="$3"

  metadata_incremented_value="$(
    awk \
      -v value="$decimal_value" \
      -v width="$decimal_width" '
      BEGIN {
        if (length(value) != width) {
          exit 1
        }

        if (value ~ /[^0-9]/) {
          exit 1
        }

        result = value
        carry = 1

        for (position = width; position >= 1; position--) {
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
  )" || {
    metadata_error="${decimal_name}_overflow"
    return 1
  }

  return 0
}

metadata_write_device_copy() {
  if [ "$#" -ne 3 ]; then
    metadata_error="write_device_copy_argument_count"
    return 1
  fi

  image_path="$1"
  copy_name="$2"
  record_path="$3"

  if [ ! -f "$image_path" ]; then
    metadata_error="image_not_regular_file"
    return 1
  fi

  if [ ! -w "$image_path" ]; then
    metadata_error="image_not_writable"
    return 1
  fi

  if [ ! -f "$record_path" ]; then
    metadata_error="source_record_missing"
    return 1
  fi

  if ! metadata_validate_device_layout; then
    return 1
  fi

  case "$copy_name" in
    A)
      record_sector="$metadata_record_a_sector"
      ;;
    B)
      record_sector="$metadata_record_b_sector"
      ;;
    *)
      metadata_error="invalid_copy_name"
      return 1
      ;;
  esac

  if dd \
    if="$record_path" \
    of="$image_path" \
    bs="$metadata_sector_size" \
    seek="$record_sector" \
    count="$metadata_record_sector_count" \
    conv=notrunc \
    2>/dev/null
  then
    :
  else
    metadata_error="image_record_write_failed"
    return 1
  fi

  if sync; then
    return 0
  else
    metadata_error="image_sync_failed"
    return 1
  fi
}

metadata_prepare_pending_image() {
  if [ "$#" -ne 2 ]; then
    metadata_error="prepare_pending_image_argument_count"
    return 1
  fi

  image_path="$1"
  work_directory="$2"
  metadata_previous_copy=""
  metadata_written_copy=""
  metadata_error=""

  if [ ! -f "$image_path" ]; then
    metadata_error="image_not_regular_file"
    return 1
  fi

  if [ ! -r "$image_path" ]; then
    metadata_error="image_not_readable"
    return 1
  fi

  if [ ! -w "$image_path" ]; then
    metadata_error="image_not_writable"
    return 1
  fi

  if ! metadata_select_device "$image_path" "$work_directory"; then
    return 1
  fi

  if [ "$metadata_pending_slot" = "-" ]; then
    metadata_error="pending_slot_missing"
    return 1
  fi

  if [ "$metadata_selection_reason" != "pending" ]; then
    metadata_error="pending_attempt_limit"
    return 1
  fi

  previous_copy="$metadata_selected_copy"
  selected_slot="$metadata_selected_slot"
  selection_reason="$metadata_selection_reason"

  if ! metadata_increment_decimal \
    generation \
    "$metadata_generation" \
    20
  then
    return 1
  fi

  next_generation="$metadata_incremented_value"

  if ! metadata_increment_decimal \
    pending_attempts \
    "$metadata_pending_attempts" \
    3
  then
    return 1
  fi

  next_pending_attempts="$metadata_incremented_value"

  case "$previous_copy" in
    A)
      target_copy="B"
      ;;
    B)
      target_copy="A"
      ;;
    *)
      metadata_error="selected_copy_invalid"
      return 1
      ;;
  esac

  next_record_path="$work_directory/atomcam2-boot-metadata-next.$$"
  verified_record_path="$work_directory/atomcam2-boot-metadata-verify.$$"

  rm -f "$next_record_path" "$verified_record_path"

  if ! metadata_write \
    "$next_record_path" \
    "$next_generation" \
    "$metadata_confirmed_slot" \
    "$metadata_pending_slot" \
    "$next_pending_attempts" \
    "$metadata_max_attempts" \
    "$metadata_slot_a_status" \
    "$metadata_slot_a_firmware_id" \
    "$metadata_slot_a_sha256" \
    "$metadata_slot_b_status" \
    "$metadata_slot_b_firmware_id" \
    "$metadata_slot_b_sha256"
  then
    rm -f "$next_record_path" "$verified_record_path"
    return 1
  fi

  expected_record_sha256="$(
    sha256sum "$next_record_path" |
      awk '{print $1}'
  )"

  if ! metadata_write_device_copy \
    "$image_path" \
    "$target_copy" \
    "$next_record_path"
  then
    rm -f "$next_record_path" "$verified_record_path"
    return 1
  fi

  if ! metadata_extract_device_copy \
    "$image_path" \
    "$target_copy" \
    "$verified_record_path"
  then
    rm -f "$next_record_path" "$verified_record_path"
    return 1
  fi

  actual_record_sha256="$(
    sha256sum "$verified_record_path" |
      awk '{print $1}'
  )"

  if [ "$actual_record_sha256" != "$expected_record_sha256" ]; then
    rm -f "$next_record_path" "$verified_record_path"
    metadata_error="written_record_verification_failed"
    return 1
  fi

  if ! metadata_read "$verified_record_path"; then
    rm -f "$next_record_path" "$verified_record_path"
    metadata_error="written_record_invalid"
    return 1
  fi

  if [ "$metadata_generation" != "$next_generation" ]; then
    rm -f "$next_record_path" "$verified_record_path"
    metadata_error="written_generation_mismatch"
    return 1
  fi

  if [ "$metadata_pending_attempts" != "$next_pending_attempts" ]; then
    rm -f "$next_record_path" "$verified_record_path"
    metadata_error="written_attempts_mismatch"
    return 1
  fi

  rm -f "$next_record_path" "$verified_record_path"

  metadata_previous_copy="$previous_copy"
  metadata_written_copy="$target_copy"
  metadata_selected_slot="$selected_slot"
  metadata_selection_reason="$selection_reason"
  metadata_error=""

  return 0
}
metadata_confirm_pending_image() {
  if [ "$#" -ne 3 ]; then
    metadata_error="confirm_pending_image_argument_count"
    return 1
  fi

  image_path="$1"
  active_slot="$2"
  work_directory="$3"
  metadata_previous_copy=""
  metadata_written_copy=""
  metadata_error=""

  if [ ! -f "$image_path" ]; then
    metadata_error="image_not_regular_file"
    return 1
  fi

  if [ ! -r "$image_path" ]; then
    metadata_error="image_not_readable"
    return 1
  fi

  if [ ! -w "$image_path" ]; then
    metadata_error="image_not_writable"
    return 1
  fi

  case "$active_slot" in
    A|B)
      ;;
    *)
      metadata_error="active_slot_invalid"
      return 1
      ;;
  esac

  if ! metadata_select_device "$image_path" "$work_directory"; then
    return 1
  fi

  if [ "$metadata_pending_slot" = "-" ]; then
    metadata_error="pending_slot_missing"
    return 1
  fi

  if [ "$active_slot" != "$metadata_pending_slot" ]; then
    metadata_error="active_slot_not_pending"
    return 1
  fi

  previous_copy="$metadata_selected_copy"

  if ! metadata_increment_decimal \
    generation \
    "$metadata_generation" \
    20
  then
    return 1
  fi

  next_generation="$metadata_incremented_value"

  case "$previous_copy" in
    A)
      target_copy="B"
      ;;
    B)
      target_copy="A"
      ;;
    *)
      metadata_error="selected_copy_invalid"
      return 1
      ;;
  esac

  next_record_path="$work_directory/atomcam2-boot-metadata-confirm.$$"
  verified_record_path="$work_directory/atomcam2-boot-metadata-confirm-verify.$$"

  rm -f "$next_record_path" "$verified_record_path"

  if ! metadata_write \
    "$next_record_path" \
    "$next_generation" \
    "$active_slot" \
    - \
    000 \
    "$metadata_max_attempts" \
    "$metadata_slot_a_status" \
    "$metadata_slot_a_firmware_id" \
    "$metadata_slot_a_sha256" \
    "$metadata_slot_b_status" \
    "$metadata_slot_b_firmware_id" \
    "$metadata_slot_b_sha256"
  then
    rm -f "$next_record_path" "$verified_record_path"
    return 1
  fi

  expected_record_sha256="$(
    sha256sum "$next_record_path" |
      awk '{print $1}'
  )"

  if ! metadata_write_device_copy \
    "$image_path" \
    "$target_copy" \
    "$next_record_path"
  then
    rm -f "$next_record_path" "$verified_record_path"
    return 1
  fi

  if ! metadata_extract_device_copy \
    "$image_path" \
    "$target_copy" \
    "$verified_record_path"
  then
    rm -f "$next_record_path" "$verified_record_path"
    return 1
  fi

  actual_record_sha256="$(
    sha256sum "$verified_record_path" |
      awk '{print $1}'
  )"

  if [ "$actual_record_sha256" != "$expected_record_sha256" ]; then
    rm -f "$next_record_path" "$verified_record_path"
    metadata_error="written_record_verification_failed"
    return 1
  fi

  if ! metadata_read "$verified_record_path"; then
    rm -f "$next_record_path" "$verified_record_path"
    metadata_error="written_record_invalid"
    return 1
  fi

  if [ "$metadata_generation" != "$next_generation" ]; then
    rm -f "$next_record_path" "$verified_record_path"
    metadata_error="written_generation_mismatch"
    return 1
  fi

  if [ "$metadata_confirmed_slot" != "$active_slot" ]; then
    rm -f "$next_record_path" "$verified_record_path"
    metadata_error="written_confirmed_slot_mismatch"
    return 1
  fi

  if [ "$metadata_pending_slot" != "-" ]; then
    rm -f "$next_record_path" "$verified_record_path"
    metadata_error="written_pending_slot_not_cleared"
    return 1
  fi

  if [ "$metadata_pending_attempts" != "000" ]; then
    rm -f "$next_record_path" "$verified_record_path"
    metadata_error="written_pending_attempts_not_reset"
    return 1
  fi

  rm -f "$next_record_path" "$verified_record_path"

  metadata_previous_copy="$previous_copy"
  metadata_written_copy="$target_copy"
  metadata_selected_slot="$active_slot"
  metadata_selection_reason="confirmed"
  metadata_error=""

  return 0
}
metadata_revert_image() {
  if [ "$#" -ne 3 ]; then
    metadata_error="revert_image_argument_count"
    return 1
  fi

  image_path="$1"
  active_slot="$2"
  work_directory="$3"
  metadata_previous_copy=""
  metadata_written_copy=""
  metadata_error=""

  if [ ! -f "$image_path" ]; then
    metadata_error="image_not_regular_file"
    return 1
  fi

  if [ ! -r "$image_path" ]; then
    metadata_error="image_not_readable"
    return 1
  fi

  if [ ! -w "$image_path" ]; then
    metadata_error="image_not_writable"
    return 1
  fi

  case "$active_slot" in
    A|B)
      ;;
    *)
      metadata_error="active_slot_invalid"
      return 1
      ;;
  esac

  if ! metadata_select_device "$image_path" "$work_directory"; then
    return 1
  fi

  if [ "$metadata_pending_slot" != "-" ]; then
    metadata_error="pending_slot_already_set"
    return 1
  fi

  if [ "$active_slot" != "$metadata_confirmed_slot" ]; then
    metadata_error="active_slot_not_confirmed"
    return 1
  fi

  case "$active_slot" in
    A)
      revert_slot="B"
      revert_slot_status="$metadata_slot_b_status"
      ;;
    B)
      revert_slot="A"
      revert_slot_status="$metadata_slot_a_status"
      ;;
  esac

  if [ "$revert_slot_status" != "valid" ]; then
    metadata_error="revert_slot_not_valid"
    return 1
  fi

  previous_copy="$metadata_selected_copy"

  if ! metadata_increment_decimal \
    generation \
    "$metadata_generation" \
    20
  then
    return 1
  fi

  next_generation="$metadata_incremented_value"

  case "$previous_copy" in
    A)
      target_copy="B"
      ;;
    B)
      target_copy="A"
      ;;
    *)
      metadata_error="selected_copy_invalid"
      return 1
      ;;
  esac

  next_record_path="$work_directory/atomcam2-boot-metadata-revert.$$"
  verified_record_path="$work_directory/atomcam2-boot-metadata-revert-verify.$$"

  rm -f "$next_record_path" "$verified_record_path"

  if ! metadata_write \
    "$next_record_path" \
    "$next_generation" \
    "$active_slot" \
    "$revert_slot" \
    000 \
    "$metadata_max_attempts" \
    "$metadata_slot_a_status" \
    "$metadata_slot_a_firmware_id" \
    "$metadata_slot_a_sha256" \
    "$metadata_slot_b_status" \
    "$metadata_slot_b_firmware_id" \
    "$metadata_slot_b_sha256"
  then
    rm -f "$next_record_path" "$verified_record_path"
    return 1
  fi

  expected_record_sha256="$(
    sha256sum "$next_record_path" |
      awk '{print $1}'
  )"

  if ! metadata_write_device_copy \
    "$image_path" \
    "$target_copy" \
    "$next_record_path"
  then
    rm -f "$next_record_path" "$verified_record_path"
    return 1
  fi

  if ! metadata_extract_device_copy \
    "$image_path" \
    "$target_copy" \
    "$verified_record_path"
  then
    rm -f "$next_record_path" "$verified_record_path"
    return 1
  fi

  actual_record_sha256="$(
    sha256sum "$verified_record_path" |
      awk '{print $1}'
  )"

  if [ "$actual_record_sha256" != "$expected_record_sha256" ]; then
    rm -f "$next_record_path" "$verified_record_path"
    metadata_error="written_record_verification_failed"
    return 1
  fi

  if ! metadata_read "$verified_record_path"; then
    rm -f "$next_record_path" "$verified_record_path"
    metadata_error="written_record_invalid"
    return 1
  fi

  if [ "$metadata_generation" != "$next_generation" ]; then
    rm -f "$next_record_path" "$verified_record_path"
    metadata_error="written_generation_mismatch"
    return 1
  fi

  if [ "$metadata_confirmed_slot" != "$active_slot" ]; then
    rm -f "$next_record_path" "$verified_record_path"
    metadata_error="written_confirmed_slot_mismatch"
    return 1
  fi

  if [ "$metadata_pending_slot" != "$revert_slot" ]; then
    rm -f "$next_record_path" "$verified_record_path"
    metadata_error="written_revert_slot_mismatch"
    return 1
  fi

  if [ "$metadata_pending_attempts" != "000" ]; then
    rm -f "$next_record_path" "$verified_record_path"
    metadata_error="written_pending_attempts_not_reset"
    return 1
  fi

  rm -f "$next_record_path" "$verified_record_path"

  metadata_previous_copy="$previous_copy"
  metadata_written_copy="$target_copy"
  metadata_selected_slot="$revert_slot"
  metadata_selection_reason="pending"
  metadata_error=""

  return 0
}
usage() {
  printf '%s\n' \
    "Usage:" \
    "  $0 write OUTPUT GENERATION CONFIRMED PENDING ATTEMPTS MAX_ATTEMPTS A_STATUS A_UUID A_SHA256 B_STATUS B_UUID B_SHA256" \
    "  $0 firmware-id SHA256" \
    "  $0 initial-record OUTPUT ROOTFS" \
    "  $0 read RECORD" \
    "  $0 choose-slot RECORD" \
    "  $0 select RECORD_A RECORD_B" \
    "  $0 select-device DEVICE [WORK_DIRECTORY]" \
    "  $0 prepare-pending-image IMAGE [WORK_DIRECTORY]" \
    "  $0 confirm-pending-image IMAGE ACTIVE_SLOT [WORK_DIRECTORY]" \
    "  $0 revert-image IMAGE ACTIVE_SLOT [WORK_DIRECTORY]"
}

command_name="${1:-}"

case "$command_name" in
  firmware-id)
    if [ "$#" -ne 2 ]; then
      usage >&2
      exit 1
    fi

    if ! metadata_firmware_id_from_sha256 "$2"; then
      printf 'atomcam2 boot metadata: %s\n' "$metadata_error" >&2
      exit 1
    fi
    ;;
  initial-record)
    if [ "$#" -ne 3 ]; then
      usage >&2
      exit 1
    fi

    if ! metadata_write_initial_record "$2" "$3"; then
      printf 'atomcam2 boot metadata: %s\n' "$metadata_error" >&2
      exit 1
    fi
    ;;
  write)
    shift

    if ! metadata_write "$@"; then
      printf 'atomcam2 boot metadata: %s\n' "$metadata_error" >&2
      exit 1
    fi
    ;;
  read)
    if [ "$#" -ne 2 ]; then
      usage >&2
      exit 1
    fi

    if metadata_read "$2"; then
      metadata_print
    else
      printf 'atomcam2 boot metadata: %s\n' "$metadata_error" >&2
      exit 1
    fi
    ;;
  choose-slot)
    if [ "$#" -ne 2 ]; then
      usage >&2
      exit 1
    fi

    if metadata_choose_slot "$2"; then
      printf 'selected_slot=%s\n' "$metadata_selected_slot"
      printf 'selection_reason=%s\n' "$metadata_selection_reason"
    else
      printf 'atomcam2 boot metadata: %s\n' "$metadata_error" >&2
      exit 1
    fi
    ;;
  select)
    if [ "$#" -ne 3 ]; then
      usage >&2
      exit 1
    fi

    if metadata_select "$2" "$3"; then
      printf '%s\n' "$metadata_selected_record"
    else
      printf 'atomcam2 boot metadata: %s\n' "$metadata_error" >&2
      exit 1
    fi
    ;;
  select-device)
    if [ "$#" -eq 2 ]; then
      work_directory="${ATOMCAM2_BOOT_METADATA_WORK_DIR:-/tmp}"
    elif [ "$#" -eq 3 ]; then
      work_directory="$3"
    else
      usage >&2
      exit 1
    fi

    if metadata_select_device "$2" "$work_directory"; then
      printf 'selected_copy=%s\n' "$metadata_selected_copy"
      printf 'selected_slot=%s\n' "$metadata_selected_slot"
      printf 'selection_reason=%s\n' "$metadata_selection_reason"
      metadata_print
    else
      printf 'atomcam2 boot metadata: %s\n' "$metadata_error" >&2
      exit 1
    fi
    ;;
  prepare-pending-image)
    if [ "$#" -eq 2 ]; then
      work_directory="${ATOMCAM2_BOOT_METADATA_WORK_DIR:-/tmp}"
    elif [ "$#" -eq 3 ]; then
      work_directory="$3"
    else
      usage >&2
      exit 1
    fi

    if metadata_prepare_pending_image "$2" "$work_directory"; then
      printf 'previous_copy=%s\n' "$metadata_previous_copy"
      printf 'written_copy=%s\n' "$metadata_written_copy"
      printf 'selected_slot=%s\n' "$metadata_selected_slot"
      printf 'selection_reason=%s\n' "$metadata_selection_reason"
      metadata_print
    else
      printf 'atomcam2 boot metadata: %s\n' "$metadata_error" >&2
      exit 1
    fi
    ;;
  confirm-pending-image)
    if [ "$#" -eq 3 ]; then
      work_directory="${ATOMCAM2_BOOT_METADATA_WORK_DIR:-/tmp}"
    elif [ "$#" -eq 4 ]; then
      work_directory="$4"
    else
      usage >&2
      exit 1
    fi

    if metadata_confirm_pending_image \
      "$2" \
      "$3" \
      "$work_directory"
    then
      printf 'previous_copy=%s\n' "$metadata_previous_copy"
      printf 'written_copy=%s\n' "$metadata_written_copy"
      metadata_print
    else
      printf 'atomcam2 boot metadata: %s\n' "$metadata_error" >&2
      exit 1
    fi
    ;;
  revert-image)
    if [ "$#" -eq 3 ]; then
      work_directory="${ATOMCAM2_BOOT_METADATA_WORK_DIR:-/tmp}"
    elif [ "$#" -eq 4 ]; then
      work_directory="$4"
    else
      usage >&2
      exit 1
    fi

    if metadata_revert_image \
      "$2" \
      "$3" \
      "$work_directory"
    then
      printf 'previous_copy=%s\n' "$metadata_previous_copy"
      printf 'written_copy=%s\n' "$metadata_written_copy"
      printf 'selected_slot=%s\n' "$metadata_selected_slot"
      printf 'selection_reason=%s\n' "$metadata_selection_reason"
      metadata_print
    else
      printf 'atomcam2 boot metadata: %s\n' "$metadata_error" >&2
      exit 1
    fi
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
