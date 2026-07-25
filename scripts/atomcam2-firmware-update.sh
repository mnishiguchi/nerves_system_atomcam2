#!/bin/sh
set -eu

PATH=/sbin:/bin:/usr/sbin:/usr/bin
export PATH

metadata_command="${ATOMCAM2_BOOT_METADATA_COMMAND:-/usr/bin/atomcam2-boot-metadata}"
fwup_command="${ATOMCAM2_FWUP_COMMAND:-/usr/bin/fwup}"
unzip_command="${ATOMCAM2_UNZIP_COMMAND:-/usr/bin/unzip}"
mount_command="${ATOMCAM2_MOUNT_COMMAND:-/bin/mount}"
umount_command="${ATOMCAM2_UMOUNT_COMMAND:-/bin/umount}"
root_disk="${ATOMCAM2_ROOT_DISK:-/dev/rootdisk0}"
boot_report="${ATOMCAM2_BOOT_REPORT:-/media/mmc/atomcam2-boot-manager.env}"
update_directory="${ATOMCAM2_UPDATE_DIRECTORY:-/data/atomcam2-update}"
work_root="${ATOMCAM2_FIRMWARE_WORK_DIRECTORY:-/tmp/atomcam2-firmware-update}"
lock_directory="${ATOMCAM2_UPDATE_LOCK_DIRECTORY:-/tmp/atomcam2-firmware-update.lock}"
allow_regular_media="${ATOMCAM2_ALLOW_REGULAR_MEDIA:-0}"
skip_root_check="${ATOMCAM2_SKIP_ROOT_CHECK:-0}"
metadata_record_a_sector=2032
metadata_record_b_sector=2040
metadata_record_sector_count=8
metadata_sector_size=512
lock_acquired=0
work_directory=""
staged_firmware=""
temporary_file=""
candidate_mount=""
candidate_mounted=0

usage() {
  printf '%s\n' \
    "Usage:" \
    "  atomcam2-firmware-update precheck" \
    "  atomcam2-firmware-update install FIRMWARE" \
    "  atomcam2-firmware-update status" \
    "  atomcam2-firmware-update confirm" \
    "  atomcam2-firmware-update revert" \
    "  atomcam2-firmware-update prevent-revert" \
    "  atomcam2-firmware-update reject-pending" \
    "  atomcam2-firmware-update factory-reset"
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_root() {
  if [ "$skip_root_check" = "1" ]; then
    return 0
  fi

  if [ "$(id -u)" -ne 0 ]; then
    fail "run this command as root"
  fi
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

slot_a_partition="${ATOMCAM2_SLOT_A_PARTITION:-$(partition_path "$root_disk" 2)}"
slot_b_partition="${ATOMCAM2_SLOT_B_PARTITION:-$(partition_path "$root_disk" 3)}"
data_partition="${ATOMCAM2_DATA_PARTITION:-$(partition_path "$root_disk" 4)}"

is_media_path() {
  media_path="$1"

  if [ -b "$media_path" ]; then
    return 0
  fi

  if [ "$allow_regular_media" = "1" ]; then
    if [ -f "$media_path" ]; then
      return 0
    fi
  fi

  return 1
}

require_media_path() {
  media_path="$1"
  media_name="$2"

  if ! is_media_path "$media_path"; then
    fail "$media_name is not available: $media_path"
  fi

  if [ ! -r "$media_path" ]; then
    fail "$media_name is not readable: $media_path"
  fi

  if [ ! -w "$media_path" ]; then
    fail "$media_name is not writable: $media_path"
  fi
}

require_command() {
  command_path="$1"
  command_name="$2"

  if [ ! -x "$command_path" ]; then
    fail "$command_name is unavailable: $command_path"
  fi
}

metadata_value() {
  key="$1"
  input_path="$2"

  awk \
    -F= \
    -v key="$key" '
      $1 == key {
        value = substr($0, length(key) + 2)
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

firmware_metadata_value() {
  key="$1"
  input_path="$2"

  awk \
    -F= \
    -v key="$key" '
      $1 == key {
        value = substr($0, length(key) + 2)
        gsub(/^"|"$/, "", value)
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

firmware_id_valid() {
  firmware_id="$1"

  awk -v firmware_id="$firmware_id" '
    function hexadecimal(value) {
      return value != "" && value !~ /[^0-9a-f]/
    }

    BEGIN {
      if (length(firmware_id) != 36) exit 1
      if (substr(firmware_id, 9, 1) != "-") exit 1
      if (substr(firmware_id, 14, 1) != "-") exit 1
      if (substr(firmware_id, 19, 1) != "-") exit 1
      if (substr(firmware_id, 24, 1) != "-") exit 1
      if (!hexadecimal(substr(firmware_id, 1, 8))) exit 1
      if (!hexadecimal(substr(firmware_id, 10, 4))) exit 1
      if (!hexadecimal(substr(firmware_id, 15, 4))) exit 1
      if (!hexadecimal(substr(firmware_id, 20, 4))) exit 1
      if (!hexadecimal(substr(firmware_id, 25, 12))) exit 1
    }
  '
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

current_boot_id() {
  if [ -r /proc/sys/kernel/random/boot_id ]; then
    cat /proc/sys/kernel/random/boot_id
  else
    printf 'unknown\n'
  fi
}

remove_stale_lock() {
  if [ ! -d "$lock_directory" ]; then
    return 0
  fi

  owner_path="$lock_directory/owner"

  if [ ! -r "$owner_path" ]; then
    rm -rf "$lock_directory"
    return 0
  fi

  owner_boot_id=""
  owner_pid=""
  read -r owner_boot_id owner_pid < "$owner_path" || true

  if [ "$owner_boot_id" = "$(current_boot_id)" ]; then
    case "$owner_pid" in
      ''|*[!0-9]*)
        ;;
      *)
        if [ -d "/proc/$owner_pid" ]; then
          return 1
        fi
        ;;
    esac
  fi

  rm -rf "$lock_directory"
}

acquire_lock() {
  lock_parent="${lock_directory%/*}"

  if [ "$lock_parent" = "$lock_directory" ]; then
    lock_parent="."
  fi

  mkdir -p "$lock_parent"

  if mkdir "$lock_directory" 2>/dev/null; then
    :
  else
    if ! remove_stale_lock; then
      fail "another firmware operation is in progress"
    fi

    if ! mkdir "$lock_directory" 2>/dev/null; then
      fail "could not acquire firmware update lock"
    fi
  fi

  printf '%s %s\n' "$(current_boot_id)" "$$" > "$lock_directory/owner"
  lock_acquired=1
}

release_lock() {
  if [ "$lock_acquired" -eq 1 ]; then
    rm -rf "$lock_directory"
    lock_acquired=0
  fi
}

cleanup() {
  if [ "$candidate_mounted" -eq 1 ]; then
    "$umount_command" "$candidate_mount" >/dev/null 2>&1 || true
    candidate_mounted=0
  fi

  if [ -n "$work_directory" ]; then
    rm -rf "$work_directory"
  fi

  if [ -n "$staged_firmware" ]; then
    rm -f "$staged_firmware"
  fi

  if [ -n "$temporary_file" ]; then
    rm -f "$temporary_file"
  fi

  release_lock
}

trap cleanup EXIT
trap 'exit 1' HUP INT TERM

prepare_work_directory() {
  requested_work_root="$1"
  mkdir -p "$requested_work_root"
  work_directory="$(mktemp -d "$requested_work_root/work.XXXXXX")"
}

load_metadata() {
  metadata_output_path="$1"
  metadata_work_directory="$2"

  "$metadata_command" \
    select-device \
    "$root_disk" \
    "$metadata_work_directory" > "$metadata_output_path"

  selected_copy="$(metadata_value selected_copy "$metadata_output_path")"
  selected_slot="$(metadata_value selected_slot "$metadata_output_path")"
  selection_reason="$(metadata_value selection_reason "$metadata_output_path")"
  generation="$(metadata_value generation "$metadata_output_path")"
  confirmed_slot="$(metadata_value confirmed_slot "$metadata_output_path")"
  pending_slot="$(metadata_value pending_slot "$metadata_output_path")"
  pending_attempts="$(metadata_value pending_attempts "$metadata_output_path")"
  max_attempts="$(metadata_value max_attempts "$metadata_output_path")"
  slot_a_status="$(metadata_value slot_a_status "$metadata_output_path")"
  slot_a_firmware_id="$(metadata_value slot_a_firmware_id "$metadata_output_path")"
  slot_a_sha256="$(metadata_value slot_a_sha256 "$metadata_output_path")"
  slot_b_status="$(metadata_value slot_b_status "$metadata_output_path")"
  slot_b_firmware_id="$(metadata_value slot_b_firmware_id "$metadata_output_path")"
  slot_b_sha256="$(metadata_value slot_b_sha256 "$metadata_output_path")"
}

boot_report_value() {
  key="$1"

  if [ -n "${ATOMCAM2_CURRENT_SLOT:-}" ]; then
    case "$key" in
      boot_policy_selected_slot)
        printf '%s\n' "$ATOMCAM2_CURRENT_SLOT"
        return 0
        ;;
      boot_policy_selection_reason)
        printf '%s\n' "${ATOMCAM2_CURRENT_SELECTION_REASON:-confirmed}"
        return 0
        ;;
      stage)
        printf 'application_root\n'
        return 0
        ;;
    esac
  fi

  metadata_value "$key" "$boot_report"
}

load_running_boot() {
  report_stage="$(boot_report_value stage)"
  running_slot="$(boot_report_value boot_policy_selected_slot)"
  running_selection_reason="$(boot_report_value boot_policy_selection_reason)"

  if [ "$report_stage" != "application_root" ]; then
    fail "boot manager did not reach the application root: $report_stage"
  fi

  case "$running_slot" in
    A|B)
      ;;
    *)
      fail "invalid running slot: $running_slot"
      ;;
  esac
}

next_metadata_copy() {
  case "$selected_copy" in
    A)
      written_copy="B"
      metadata_sector="$metadata_record_b_sector"
      ;;
    B)
      written_copy="A"
      metadata_sector="$metadata_record_a_sector"
      ;;
    *)
      fail "invalid selected metadata copy: $selected_copy"
      ;;
  esac
}

write_next_metadata() {
  operation_name="$1"
  metadata_state_path="$2"

  next_generation="$(increment_generation "$generation")"
  next_record_path="$work_directory/metadata-${operation_name}.bin"

  "$metadata_command" write \
    "$next_record_path" \
    "$next_generation" \
    "$confirmed_slot" \
    "$pending_slot" \
    "$pending_attempts" \
    "$max_attempts" \
    "$slot_a_status" \
    "$slot_a_firmware_id" \
    "$slot_a_sha256" \
    "$slot_b_status" \
    "$slot_b_firmware_id" \
    "$slot_b_sha256"

  next_metadata_copy

  metadata_write_failed=0

  if dd \
    if="$next_record_path" \
    of="$root_disk" \
    bs="$metadata_sector_size" \
    seek="$metadata_sector" \
    count="$metadata_record_sector_count" \
    conv=notrunc,fsync \
    status=none
  then
    :
  else
    metadata_write_failed=1
  fi

  verify_directory="$work_directory/verify-$operation_name"
  mkdir -p "$verify_directory"
  load_metadata "$metadata_state_path" "$verify_directory"

  if [ "$generation" != "$next_generation" ]; then
    if [ "$metadata_write_failed" -eq 1 ]; then
      fail "metadata write failed and the next generation was not selected"
    fi

    fail "metadata generation verification failed"
  fi

  printf 'written_metadata_copy=%s\n' "$written_copy"
  printf 'metadata_generation=%s\n' "$generation"
}

media_size() {
  media_path="$1"

  if [ -b "$media_path" ]; then
    resolved_media_path="$(readlink -f "$media_path")"
    block_name="${resolved_media_path##*/}"
    block_size_path="/sys/class/block/$block_name/size"

    if [ ! -r "$block_size_path" ]; then
      fail "could not determine media size: $media_path"
    fi

    awk -v sectors="$(cat "$block_size_path")" 'BEGIN { print sectors * 512 }'
  else
    wc -c < "$media_path" | tr -d ' '
  fi
}

path_is_mounted() {
  media_path="$1"
  resolved_path="$(readlink -f "$media_path" 2>/dev/null || printf '%s\n' "$media_path")"

  awk \
    -v media_path="$media_path" \
    -v resolved_path="$resolved_path" '
      $1 == media_path || $1 == resolved_path {
        found = 1
      }

      END {
        exit(found ? 0 : 1)
      }
    ' \
    /proc/mounts
}

require_base_state() {
  require_root
  require_command "$metadata_command" "boot metadata command"
  require_media_path "$root_disk" "root disk"
  require_media_path "$slot_a_partition" "application slot A"
  require_media_path "$slot_b_partition" "application slot B"
}

check_update_preconditions() {
  require_base_state
  require_command "$fwup_command" "fwup"
  require_command "$unzip_command" "unzip"

  mkdir -p "$update_directory"

  update_probe="$update_directory/.write-probe.$$"
  if ! : > "$update_probe"; then
    fail "firmware staging directory is not writable: $update_directory"
  fi
  rm -f "$update_probe"

  if [ -d "$lock_directory" ]; then
    if ! remove_stale_lock; then
      fail "another firmware operation is in progress"
    fi
  fi

  mkdir -p "$work_root"
  precheck_work_directory="$(mktemp -d "$work_root/precheck.XXXXXX")"
  precheck_state_path="$precheck_work_directory/state.env"
  load_metadata "$precheck_state_path" "$precheck_work_directory"
  load_running_boot
  rm -rf "$precheck_work_directory"

  if [ "$pending_slot" != "-" ]; then
    fail "a pending firmware slot already exists: $pending_slot"
  fi

  if [ "$running_slot" != "$confirmed_slot" ]; then
    fail "running slot is not the confirmed slot"
  fi
}

command_precheck() {
  check_update_preconditions
  printf 'status=ready\n'
  printf 'confirmed_slot=%s\n' "$confirmed_slot"
}

command_status() {
  require_base_state
  prepare_work_directory "$work_root"
  state_path="$work_directory/state.env"
  state_work_directory="$work_directory/state"
  mkdir -p "$state_work_directory"
  load_metadata "$state_path" "$state_work_directory"
  load_running_boot

  active_slot="$(printf '%s' "$running_slot" | tr 'A-Z' 'a-z')"
  next_slot="$(printf '%s' "$selected_slot" | tr 'A-Z' 'a-z')"

  if [ "$active_slot" = "$next_slot" ]; then
    printf '%s\n' "$active_slot"
  else
    printf '%s->%s\n' "$active_slot" "$next_slot"
  fi
}

validate_firmware_metadata() {
  firmware_path="$1"
  metadata_path="$2"

  if ! "$fwup_command" -m -i "$firmware_path" > "$metadata_path"; then
    fail "could not read firmware metadata"
  fi

  firmware_platform="$(firmware_metadata_value meta-platform "$metadata_path")"
  firmware_architecture="$(firmware_metadata_value meta-architecture "$metadata_path")"
  firmware_uuid="$(firmware_metadata_value meta-uuid "$metadata_path")"

  if [ "$firmware_platform" != "atomcam2" ]; then
    fail "firmware platform is not atomcam2: $firmware_platform"
  fi

  if [ "$firmware_architecture" != "mipsel" ]; then
    fail "firmware architecture is not mipsel: $firmware_architecture"
  fi

  if ! firmware_id_valid "$firmware_uuid"; then
    fail "firmware UUID is invalid: $firmware_uuid"
  fi
}

validate_candidate_rootfs() {
  candidate_mount="$work_directory/candidate-root"
  mkdir -p "$candidate_mount"

  if ! "$mount_command" \
    -t squashfs \
    -o ro \
    "$candidate_partition" \
    "$candidate_mount"
  then
    fail "candidate root filesystem could not be mounted"
  fi

  candidate_mounted=1

  if [ ! -x "$candidate_mount/sbin/init" ]; then
    fail "candidate root filesystem is missing executable /sbin/init"
  fi

  candidate_umount_found=0
  for candidate_umount in /bin/umount /sbin/umount; do
    if [ -x "$candidate_mount$candidate_umount" ]; then
      candidate_umount_found=1
      break
    fi
  done

  if [ "$candidate_umount_found" -ne 1 ]; then
    fail "candidate root filesystem is missing an unmount command"
  fi

  for required_directory in boot dev media/mmc mnt/boot-manager proc sys; do
    if [ ! -d "$candidate_mount/$required_directory" ]; then
      fail "candidate root filesystem is missing /$required_directory"
    fi
  done

  if ! "$umount_command" "$candidate_mount"; then
    fail "candidate root filesystem could not be unmounted"
  fi

  candidate_mounted=0
}

install_locked() {
  firmware_path="$1"

  if [ ! -f "$firmware_path" ]; then
    fail "firmware not found: $firmware_path"
  fi

  if [ ! -s "$firmware_path" ]; then
    fail "firmware is empty: $firmware_path"
  fi

  require_base_state
  require_command "$fwup_command" "fwup"
  require_command "$unzip_command" "unzip"
  require_command "$mount_command" "mount"
  require_command "$umount_command" "umount"
  prepare_work_directory "$update_directory"

  firmware_metadata_path="$work_directory/firmware-metadata.env"
  rootfs_path="$work_directory/rootfs.img"
  initial_state_path="$work_directory/initial-state.env"
  initial_state_work_directory="$work_directory/initial-state"
  mkdir -p "$initial_state_work_directory"

  validate_firmware_metadata "$firmware_path" "$firmware_metadata_path"

  if ! "$unzip_command" -p "$firmware_path" data/rootfs.img > "$rootfs_path"; then
    fail "failed to extract data/rootfs.img"
  fi

  if [ ! -s "$rootfs_path" ]; then
    fail "extracted rootfs.img is empty"
  fi

  rootfs_size="$(wc -c < "$rootfs_path" | tr -d ' ')"
  rootfs_sha256="$(sha256sum "$rootfs_path" | awk '{print $1}')"
  rootfs_firmware_id="$firmware_uuid"

  load_metadata "$initial_state_path" "$initial_state_work_directory"
  initial_generation="$generation"
  initial_confirmed_slot="$confirmed_slot"
  load_running_boot

  if [ "$pending_slot" != "-" ]; then
    fail "a pending firmware slot already exists: $pending_slot"
  fi

  if [ "$running_slot" != "$confirmed_slot" ]; then
    fail "running slot is not the confirmed slot"
  fi

  case "$confirmed_slot" in
    A)
      candidate_slot="B"
      candidate_partition="$slot_b_partition"
      ;;
    B)
      candidate_slot="A"
      candidate_partition="$slot_a_partition"
      ;;
    *)
      fail "invalid confirmed slot: $confirmed_slot"
      ;;
  esac

  require_media_path "$candidate_partition" "candidate partition"

  if path_is_mounted "$candidate_partition"; then
    fail "candidate partition is mounted: $candidate_partition"
  fi

  candidate_partition_size="$(media_size "$candidate_partition")"
  if [ "$rootfs_size" -gt "$candidate_partition_size" ]; then
    fail "rootfs does not fit in $candidate_partition"
  fi

  printf '%s\n' \
    "status=writing" \
    "confirmed_slot=$confirmed_slot" \
    "candidate_slot=$candidate_slot" \
    "candidate_partition=$candidate_partition" \
    "candidate_firmware_id=$rootfs_firmware_id" \
    "candidate_sha256=$rootfs_sha256"

  "$fwup_command" \
    -a \
    -i "$firmware_path" \
    -d "$candidate_partition" \
    -t atomcam2-slot

  verified_rootfs_sha256="$(
    head -c "$rootfs_size" "$candidate_partition" |
      sha256sum |
      awk '{print $1}'
  )"

  if [ "$verified_rootfs_sha256" != "$rootfs_sha256" ]; then
    fail "candidate partition verification failed"
  fi

  validate_candidate_rootfs

  before_commit_state_path="$work_directory/before-commit-state.env"
  before_commit_work_directory="$work_directory/before-commit-state"
  mkdir -p "$before_commit_work_directory"
  load_metadata "$before_commit_state_path" "$before_commit_work_directory"

  if [ "$generation" != "$initial_generation" ]; then
    fail "boot metadata changed during firmware installation"
  fi

  if [ "$confirmed_slot" != "$initial_confirmed_slot" ]; then
    fail "confirmed slot changed during firmware installation"
  fi

  if [ "$pending_slot" != "-" ]; then
    fail "pending slot changed during firmware installation"
  fi

  pending_slot="$candidate_slot"
  pending_attempts="000"

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

  committed_state_path="$work_directory/committed-state.env"
  write_next_metadata install "$committed_state_path"

  if [ "$pending_slot" != "$candidate_slot" ]; then
    fail "pending slot verification failed"
  fi

  printf '%s\n' \
    "status=installed" \
    "confirmed_slot=$confirmed_slot" \
    "candidate_slot=$candidate_slot" \
    "candidate_partition=$candidate_partition" \
    "candidate_firmware_id=$rootfs_firmware_id" \
    "candidate_sha256=$rootfs_sha256"
}

command_install() {
  if [ "$#" -ne 1 ]; then
    usage >&2
    exit 1
  fi

  acquire_lock
  install_locked "$1"
}

command_stream() {
  acquire_lock
  mkdir -p "$update_directory"
  staged_firmware="$(mktemp "$update_directory/candidate.XXXXXX")"

  if ! cat > "$staged_firmware"; then
    fail "firmware transfer failed"
  fi

  if [ ! -s "$staged_firmware" ]; then
    fail "received firmware is empty"
  fi

  install_locked "$staged_firmware"
  rm -f "$staged_firmware"
  staged_firmware=""
}

load_mutable_state() {
  require_base_state
  prepare_work_directory "$work_root"
  mutable_state_path="$work_directory/state.env"
  mutable_state_work_directory="$work_directory/state"
  mkdir -p "$mutable_state_work_directory"
  load_metadata "$mutable_state_path" "$mutable_state_work_directory"
  load_running_boot
}

command_confirm() {
  acquire_lock
  load_mutable_state

  if [ "$pending_slot" = "-" ]; then
    fail "no pending firmware exists"
  fi

  if [ "$running_slot" != "$pending_slot" ]; then
    fail "running slot is not the pending slot"
  fi

  confirmed_slot="$running_slot"
  pending_slot="-"
  pending_attempts="000"
  confirmed_state_path="$work_directory/confirmed-state.env"
  write_next_metadata confirm "$confirmed_state_path"

  if [ "$confirmed_slot" != "$running_slot" ]; then
    fail "confirmed slot verification failed"
  fi

  if [ "$pending_slot" != "-" ]; then
    fail "pending slot was not cleared"
  fi

  printf 'status=confirmed\n'
  printf 'confirmed_slot=%s\n' "$confirmed_slot"
}

command_revert() {
  acquire_lock
  load_mutable_state

  if [ "$pending_slot" != "-" ]; then
    fail "cannot revert while a pending slot exists"
  fi

  if [ "$running_slot" != "$confirmed_slot" ]; then
    fail "running slot is not the confirmed slot"
  fi

  case "$running_slot" in
    A)
      revert_slot="B"
      revert_status="$slot_b_status"
      ;;
    B)
      revert_slot="A"
      revert_status="$slot_a_status"
      ;;
  esac

  if [ "$revert_status" != "valid" ]; then
    fail "revert slot is not valid: $revert_slot"
  fi

  pending_slot="$revert_slot"
  pending_attempts="000"
  reverted_state_path="$work_directory/reverted-state.env"
  write_next_metadata revert "$reverted_state_path"

  if [ "$pending_slot" != "$revert_slot" ]; then
    fail "revert slot verification failed"
  fi

  printf 'status=revert-pending\n'
  printf 'pending_slot=%s\n' "$pending_slot"
}

command_prevent_revert() {
  acquire_lock
  load_mutable_state

  if [ "$pending_slot" != "-" ]; then
    fail "cannot prevent revert while a pending slot exists"
  fi

  if [ "$running_slot" != "$confirmed_slot" ]; then
    fail "running slot is not the confirmed slot"
  fi

  case "$running_slot" in
    A)
      if [ "$slot_b_status" != "valid" ]; then
        fail "rollback slot B is not valid"
      fi
      slot_b_status="empty"
      slot_b_firmware_id="-"
      slot_b_sha256="-"
      ;;
    B)
      if [ "$slot_a_status" != "valid" ]; then
        fail "rollback slot A is not valid"
      fi
      slot_a_status="empty"
      slot_a_firmware_id="-"
      slot_a_sha256="-"
      ;;
  esac

  prevented_state_path="$work_directory/prevented-state.env"
  write_next_metadata prevent-revert "$prevented_state_path"
  printf 'status=revert-prevented\n'
}

command_reject_pending() {
  acquire_lock
  load_mutable_state

  if [ "$pending_slot" = "-" ]; then
    fail "no pending firmware exists"
  fi

  if [ "$running_slot" != "$confirmed_slot" ]; then
    fail "running slot is not the confirmed slot"
  fi

  if [ "$running_selection_reason" != "pending_attempt_limit" ]; then
    fail "pending firmware has not exhausted its boot attempts"
  fi

  rejected_slot="$pending_slot"

  case "$rejected_slot" in
    A)
      slot_a_status="bad"
      ;;
    B)
      slot_b_status="bad"
      ;;
  esac

  pending_slot="-"
  pending_attempts="000"
  rejected_state_path="$work_directory/rejected-state.env"
  write_next_metadata reject-pending "$rejected_state_path"

  if [ "$pending_slot" != "-" ]; then
    fail "rejected pending slot was not cleared"
  fi

  printf 'status=pending-rejected\n'
  printf 'rejected_slot=%s\n' "$rejected_slot"
}

command_factory_reset() {
  acquire_lock
  require_root
  require_media_path "$data_partition" "data partition"

  marker_size=$((512 * 256))
  marker_path="${TMPDIR:-/tmp}/atomcam2-factory-reset-marker.$$"
  temporary_file="$marker_path"

  if ! dd if=/dev/zero bs="$marker_size" count=1 status=none |
    tr '\000' '\377' > "$marker_path"
  then
    rm -f "$marker_path"
    fail "could not create factory-reset marker"
  fi

  dd \
    if="$marker_path" \
    of="$data_partition" \
    bs="$marker_size" \
    count=1 \
    conv=notrunc,fsync \
    status=none

  rm -f "$marker_path"
  temporary_file=""
  printf 'status=factory-reset-pending\n'
}

command_name="${1:-}"
if [ "$#" -gt 0 ]; then
  shift
fi

case "$command_name" in
  precheck)
    if [ "$#" -ne 0 ]; then
      usage >&2
      exit 1
    fi
    command_precheck
    ;;
  install)
    command_install "$@"
    ;;
  stream)
    command_stream "$@"
    ;;
  status)
    if [ "$#" -ne 0 ]; then
      usage >&2
      exit 1
    fi
    command_status
    ;;
  confirm)
    if [ "$#" -ne 0 ]; then
      usage >&2
      exit 1
    fi
    command_confirm
    ;;
  revert)
    if [ "$#" -ne 0 ]; then
      usage >&2
      exit 1
    fi
    command_revert
    ;;
  prevent-revert)
    if [ "$#" -ne 0 ]; then
      usage >&2
      exit 1
    fi
    command_prevent_revert
    ;;
  reject-pending)
    if [ "$#" -ne 0 ]; then
      usage >&2
      exit 1
    fi
    command_reject_pending
    ;;
  factory-reset)
    if [ "$#" -ne 0 ]; then
      usage >&2
      exit 1
    fi
    command_factory_reset
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
