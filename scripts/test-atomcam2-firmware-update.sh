#!/bin/sh
set -eu

script_directory="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
source_directory="$(CDPATH= cd -- "$script_directory/../scripts" && pwd)"
work_directory="$(mktemp -d)"

cleanup() {
  rm -rf "$work_directory"
}
trap cleanup EXIT HUP INT TERM

fail() {
  printf 'test failure: %s\n' "$*" >&2
  exit 1
}

assert_equal() {
  expected="$1"
  actual="$2"
  description="$3"

  if [ "$actual" != "$expected" ]; then
    fail "$description: expected '$expected', got '$actual'"
  fi
}

assert_contains() {
  pattern="$1"
  input_path="$2"
  description="$3"

  if ! grep -Fq "$pattern" "$input_path"; then
    fail "$description: missing '$pattern'"
  fi
}

state_value() {
  key="$1"
  awk -F= -v key="$key" '$1 == key { print substr($0, length(key) + 2) }' "$FAKE_METADATA_STATE"
}

write_state() {
  cat > "$FAKE_METADATA_STATE"
}

fake_metadata="$work_directory/atomcam2-boot-metadata"
fake_fwup="$work_directory/fwup"
root_disk="$work_directory/root-disk.img"
slot_a="$work_directory/slot-a.img"
slot_b="$work_directory/slot-b.img"
data_partition="$work_directory/data.img"
update_directory="$work_directory/update"
firmware_directory="$work_directory/firmware"
firmware_path="$work_directory/candidate.fw"
invalid_firmware_path="$work_directory/invalid.fw"
export FAKE_METADATA_STATE="$work_directory/metadata.env"
export FAKE_METADATA_NEXT_STATE="$work_directory/metadata-next.env"

cat > "$fake_metadata" <<'EOF_METADATA'
#!/bin/sh
set -eu

state_file="$FAKE_METADATA_STATE"
next_state_file="$FAKE_METADATA_NEXT_STATE"

value() {
  key="$1"
  awk -F= -v key="$key" '$1 == key { print substr($0, length(key) + 2) }' "$state_file"
}

case "$1" in
  select-device)
    if [ -f "$next_state_file" ]; then
      mv "$next_state_file" "$state_file"
    fi

    cat "$state_file"
    ;;
  firmware-id)
    sha256="$2"
    printf '%s-%s-%s-%s-%s\n' \
      "$(printf '%s' "$sha256" | cut -c1-8)" \
      "$(printf '%s' "$sha256" | cut -c9-12)" \
      "$(printf '%s' "$sha256" | cut -c13-16)" \
      "$(printf '%s' "$sha256" | cut -c17-20)" \
      "$(printf '%s' "$sha256" | cut -c21-32)"
    ;;
  write)
    output_path="$2"
    generation="$3"
    confirmed_slot="$4"
    pending_slot="$5"
    pending_attempts="$6"
    max_attempts="$7"
    slot_a_status="$8"
    slot_a_firmware_id="$9"
    shift 9
    slot_a_sha256="$1"
    slot_b_status="$2"
    slot_b_firmware_id="$3"
    slot_b_sha256="$4"

    selected_copy="$(value selected_copy)"
    case "$selected_copy" in
      A) next_copy=B ;;
      B) next_copy=A ;;
      *) exit 1 ;;
    esac

    if [ "$pending_slot" = "-" ]; then
      selected_slot="$confirmed_slot"
      selection_reason=confirmed
    elif [ "$pending_attempts" -ge "$max_attempts" ]; then
      selected_slot="$confirmed_slot"
      selection_reason=pending_attempt_limit
    else
      selected_slot="$pending_slot"
      selection_reason=pending
    fi

    cat > "$next_state_file" <<EOF_STATE
selected_copy=$next_copy
selected_slot=$selected_slot
selection_reason=$selection_reason
generation=$generation
confirmed_slot=$confirmed_slot
pending_slot=$pending_slot
pending_attempts=$pending_attempts
max_attempts=$max_attempts
slot_a_status=$slot_a_status
slot_a_firmware_id=$slot_a_firmware_id
slot_a_sha256=$slot_a_sha256
slot_b_status=$slot_b_status
slot_b_firmware_id=$slot_b_firmware_id
slot_b_sha256=$slot_b_sha256
EOF_STATE

    dd if=/dev/zero of="$output_path" bs=4096 count=1 status=none
    ;;
  *)
    exit 1
    ;;
esac
EOF_METADATA
chmod +x "$fake_metadata"

cat > "$fake_fwup" <<'EOF_FWUP'
#!/bin/sh
set -eu

mode=""
firmware_path=""
destination_path=""
task_name=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -m)
      mode=metadata
      shift
      ;;
    -a)
      mode=apply
      shift
      ;;
    -i)
      firmware_path="$2"
      shift 2
      ;;
    -d)
      destination_path="$2"
      shift 2
      ;;
    -t)
      task_name="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

case "$mode" in
  metadata)
    if unzip -p "$firmware_path" data/platform >/dev/null 2>&1; then
      platform="$(unzip -p "$firmware_path" data/platform)"
    else
      platform=atomcam2
    fi

    printf 'meta-platform=%s\n' "$platform"
    printf 'meta-architecture=mipsel\n'
    ;;
  apply)
    if [ "$task_name" != "atomcam2-slot" ]; then
      exit 1
    fi

    unzip -p "$firmware_path" data/rootfs.img > "$destination_path"
    ;;
  *)
    exit 1
    ;;
esac
EOF_FWUP
chmod +x "$fake_fwup"

truncate -s 2097152 "$root_disk"
truncate -s 1048576 "$slot_a"
truncate -s 1048576 "$slot_b"
truncate -s 1048576 "$data_partition"
printf 'confirmed firmware A\n' > "$slot_a"
slot_a_before="$(sha256sum "$slot_a" | awk '{print $1}')"

mkdir -p "$firmware_directory/data" "$update_directory"
printf 'candidate firmware B\n' > "$firmware_directory/data/rootfs.img"
printf 'atomcam2\n' > "$firmware_directory/data/platform"
(
  cd "$firmware_directory"
  zip -q -r "$firmware_path" data
)
printf 'wrong-platform\n' > "$firmware_directory/data/platform"
(
  cd "$firmware_directory"
  zip -q -r "$invalid_firmware_path" data
)

initial_sha="$(sha256sum "$slot_a" | awk '{print $1}')"
initial_id="$("$fake_metadata" firmware-id "$initial_sha")"
write_state <<EOF_STATE
selected_copy=A
selected_slot=A
selection_reason=confirmed
generation=00000000000000000001
confirmed_slot=A
pending_slot=-
pending_attempts=000
max_attempts=003
slot_a_status=valid
slot_a_firmware_id=$initial_id
slot_a_sha256=$initial_sha
slot_b_status=empty
slot_b_firmware_id=-
slot_b_sha256=-
EOF_STATE

export ATOMCAM2_BOOT_METADATA_COMMAND="$fake_metadata"
export ATOMCAM2_FWUP_COMMAND="$fake_fwup"
export ATOMCAM2_UNZIP_COMMAND="$(command -v unzip)"
export ATOMCAM2_ROOT_DISK="$root_disk"
export ATOMCAM2_SLOT_A_PARTITION="$slot_a"
export ATOMCAM2_SLOT_B_PARTITION="$slot_b"
export ATOMCAM2_DATA_PARTITION="$data_partition"
export ATOMCAM2_UPDATE_DIRECTORY="$update_directory"
export ATOMCAM2_FIRMWARE_WORK_DIRECTORY="$work_directory/runtime-work"
export ATOMCAM2_UPDATE_LOCK_DIRECTORY="$work_directory/update.lock"
export ATOMCAM2_ALLOW_REGULAR_MEDIA=1
export ATOMCAM2_SKIP_ROOT_CHECK=1
export ATOMCAM2_CURRENT_SLOT=A
export ATOMCAM2_CURRENT_SELECTION_REASON=confirmed

updater="$source_directory/atomcam2-firmware-update.sh"

precheck_output="$work_directory/precheck.out"
"$updater" precheck > "$precheck_output"
assert_contains 'status=ready' "$precheck_output" 'precheck'

install_output="$work_directory/install.out"
"$updater" install "$firmware_path" > "$install_output"
assert_contains 'status=installed' "$install_output" 'install result'
assert_equal B "$(state_value pending_slot)" 'pending slot after install'
assert_equal A "$(state_value confirmed_slot)" 'confirmed slot after install'
assert_equal valid "$(state_value slot_b_status)" 'slot B status after install'
assert_equal "$slot_a_before" "$(sha256sum "$slot_a" | awk '{print $1}')" 'active slot preservation'
assert_equal a\-\>b "$("$updater" status)" 'status after install'

export ATOMCAM2_CURRENT_SLOT=B
export ATOMCAM2_CURRENT_SELECTION_REASON=pending
confirm_output="$work_directory/confirm.out"
"$updater" confirm > "$confirm_output"
assert_contains 'status=confirmed' "$confirm_output" 'confirm result'
assert_equal B "$(state_value confirmed_slot)" 'confirmed slot after confirmation'
assert_equal - "$(state_value pending_slot)" 'pending slot after confirmation'
assert_equal b "$("$updater" status)" 'status after confirmation'

revert_output="$work_directory/revert.out"
"$updater" revert > "$revert_output"
assert_contains 'status=revert-pending' "$revert_output" 'revert result'
assert_equal A "$(state_value pending_slot)" 'pending slot after revert'
assert_equal b\-\>a "$("$updater" status)" 'status after revert'

export ATOMCAM2_CURRENT_SLOT=A
export ATOMCAM2_CURRENT_SELECTION_REASON=pending
"$updater" confirm >/dev/null
assert_equal A "$(state_value confirmed_slot)" 'confirmed slot after revert confirmation'

"$updater" prevent-revert > "$work_directory/prevent.out"
assert_equal empty "$(state_value slot_b_status)" 'rollback slot after prevent-revert'

write_state <<EOF_STATE
selected_copy=A
selected_slot=A
selection_reason=pending_attempt_limit
generation=00000000000000000020
confirmed_slot=A
pending_slot=B
pending_attempts=003
max_attempts=003
slot_a_status=valid
slot_a_firmware_id=$initial_id
slot_a_sha256=$initial_sha
slot_b_status=valid
slot_b_firmware_id=11111111-1111-1111-1111-111111111111
slot_b_sha256=1111111111111111111111111111111111111111111111111111111111111111
EOF_STATE
export ATOMCAM2_CURRENT_SLOT=A
export ATOMCAM2_CURRENT_SELECTION_REASON=pending_attempt_limit
"$updater" reject-pending > "$work_directory/reject.out"
assert_equal - "$(state_value pending_slot)" 'pending slot after rejection'
assert_equal bad "$(state_value slot_b_status)" 'rejected slot status'

if "$updater" install "$invalid_firmware_path" > "$work_directory/invalid.out" 2>&1; then
  fail 'invalid platform firmware was accepted'
fi
assert_contains 'firmware platform is not atomcam2' "$work_directory/invalid.out" 'invalid platform rejection'

export ATOMCAM2_FIRMWARE_UPDATE_COMMAND="$updater"
ops_adapter="$source_directory/atomcam2-fwup-ops.sh"
assert_equal a "$("$ops_adapter" -a -i /usr/share/fwup/ops.fw -d "$root_disk" -t status)" \
  'fwup operations status adapter'

framed_status_output="$work_directory/framed-status.out"
"$ops_adapter" \
  -a \
  -i /usr/share/fwup/ops.fw \
  -d "$root_disk" \
  -t status \
  --framing > "$framed_status_output"
framed_status_hex="$(od -An -tx1 "$framed_status_output" | tr -d ' \n')"
assert_equal 00000005574e000061 "$framed_status_hex" \
  'fwup operations framed status adapter'

if "$ops_adapter" \
  -a \
  -i /usr/share/fwup/ops.fw \
  -d "$slot_a" \
  -t status \
  --framing > "$work_directory/invalid-ops-device.out"
then
  fail 'fwup operations adapter accepted an unexpected device'
fi
invalid_ops_frame_type="$(
  tail -c +5 "$work_directory/invalid-ops-device.out" |
    head -c 4 |
    od -An -tx1 |
    tr -d ' \n'
)"
assert_equal 45520000 "$invalid_ops_frame_type" \
  'fwup operations framed error type'
invalid_ops_frame_size="$(wc -c < "$work_directory/invalid-ops-device.out" | tr -d ' ')"
invalid_ops_payload_size=$((invalid_ops_frame_size - 4))
invalid_ops_frame_length="$(
  head -c 4 "$work_directory/invalid-ops-device.out" |
    od -An -tx1 |
    tr -d ' \n'
)"
assert_equal "$(printf '%08x' "$invalid_ops_payload_size")" "$invalid_ops_frame_length" \
  'fwup operations framed error length'
tail -c +9 "$work_directory/invalid-ops-device.out" > "$work_directory/invalid-ops-message.out"
assert_contains 'unexpected firmware operation device' \
  "$work_directory/invalid-ops-message.out" \
  'fwup operations device rejection'

"$ops_adapter" -a -i /usr/share/fwup/ops.fw -d "$root_disk" -t factory-reset \
  > "$work_directory/factory-reset.out"
factory_reset_prefix="$(head -c 16 "$data_partition" | od -An -tx1 | tr -d ' \n')"
assert_equal ffffffffffffffffffffffffffffffff "$factory_reset_prefix" 'factory-reset marker'

printf 'ok: atomcam2 firmware update tests passed\n'
