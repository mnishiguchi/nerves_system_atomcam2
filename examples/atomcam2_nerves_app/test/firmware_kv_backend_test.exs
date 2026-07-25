defmodule Atomcam2NervesApp.FirmwareKVBackendTest do
  use ExUnit.Case, async: true

  alias Atomcam2NervesApp.FirmwareKVBackend

  test "selects Slot A from the boot report" do
    report = """
    stage=application_root
    boot_policy_selected_slot=A
    boot_policy_selection_reason=confirmed
    """

    assert FirmwareKVBackend.active_partition_from_report(report) == "a"
  end

  test "selects Slot B from the boot report" do
    report = """
    stage=application_root
    boot_policy_selected_slot=B
    boot_policy_selection_reason=pending
    """

    assert FirmwareKVBackend.active_partition_from_report(report) == "b"
  end

  test "falls back to Slot A for an invalid report" do
    assert FirmwareKVBackend.active_partition_from_report("stage=application_root\n") == "a"
  end
end
