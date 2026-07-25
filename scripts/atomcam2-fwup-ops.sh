#!/bin/sh
set -eu

PATH=/sbin:/bin:/usr/sbin:/usr/bin
LC_ALL=C
export PATH LC_ALL

update_command="${ATOMCAM2_FIRMWARE_UPDATE_COMMAND:-/usr/bin/atomcam2-firmware-update}"
task_name=""
root_disk="${ATOMCAM2_ROOT_DISK:-/dev/rootdisk0}"
device_path="$root_disk"
framing=0

emit_byte() {
  byte_value="$1"
  octal_value="$(printf '%03o' "$byte_value")"
  printf "\\$octal_value"
}

emit_frame() {
  frame_type="$1"
  frame_message="$2"
  frame_length=$((4 + ${#frame_message}))

  emit_byte $(((frame_length >> 24) & 255))
  emit_byte $(((frame_length >> 16) & 255))
  emit_byte $(((frame_length >> 8) & 255))
  emit_byte $((frame_length & 255))
  printf '%s\000\000%s' "$frame_type" "$frame_message"
}

report_error() {
  error_message="$1"

  if [ "$framing" -eq 1 ]; then
    emit_frame ER "$error_message"
  else
    printf 'error: %s\n' "$error_message" >&2
  fi

  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -t|--task)
      if [ "$#" -lt 2 ]; then
        printf 'error: missing firmware operation task\n' >&2
        exit 1
      fi
      task_name="$2"
      shift 2
      ;;
    --task=*)
      task_name="${1#--task=}"
      shift
      ;;
    -d|--device)
      if [ "$#" -lt 2 ]; then
        printf 'error: missing firmware operation device\n' >&2
        exit 1
      fi
      device_path="$2"
      shift 2
      ;;
    --device=*)
      device_path="${1#--device=}"
      shift
      ;;
    -i|--input)
      if [ "$#" -lt 2 ]; then
        printf 'error: missing operations firmware path\n' >&2
        exit 1
      fi
      shift 2
      ;;
    --input=*)
      shift
      ;;
    --framing)
      framing=1
      shift
      ;;
    -a|--apply|--unsafe|--no-unmount|--no-eject)
      shift
      ;;
    *)
      shift
      ;;
  esac
done

if [ ! -x "$update_command" ]; then
  report_error "firmware update command is unavailable: $update_command"
fi

if [ "$device_path" != "$root_disk" ]; then
  report_error "unexpected firmware operation device: $device_path"
fi

case "$task_name" in
  status)
    operation=status
    ;;
  validate)
    operation=confirm
    ;;
  revert)
    operation=revert
    ;;
  prevent-revert)
    operation=prevent-revert
    ;;
  factory-reset)
    operation=factory-reset
    ;;
  *)
    report_error "unsupported firmware operation: $task_name"
    ;;
esac

if operation_output="$("$update_command" "$operation" 2>&1)"; then
  operation_status=0
else
  operation_status=$?
fi

if [ "$operation_status" -ne 0 ]; then
  if [ -z "$operation_output" ]; then
    operation_output="firmware operation failed: $task_name"
  fi

  if [ "$framing" -eq 1 ]; then
    emit_frame ER "$operation_output"
  else
    printf '%s\n' "$operation_output" >&2
  fi

  exit "$operation_status"
fi

if [ "$framing" -eq 1 ]; then
  if [ "$task_name" = "status" ]; then
    emit_frame WN "$operation_output"
  else
    emit_frame OK "$operation_output"
  fi
elif [ -n "$operation_output" ]; then
  printf '%s\n' "$operation_output"
fi
