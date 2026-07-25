defmodule Atomcam2NervesApp.FirmwareHealthTest do
  use ExUnit.Case, async: true

  alias Atomcam2NervesApp.FirmwareHealth

  test "validates the selected pending slot" do
    report = %{
      "stage" => "application_root",
      "boot_policy_selected_slot" => "B",
      "boot_policy_selection_reason" => "pending",
      "boot_metadata_confirmed_slot" => "A",
      "boot_metadata_pending_slot" => "B"
    }

    assert FirmwareHealth.boot_action(report) == :validate
  end

  test "rejects a pending slot after the attempt limit" do
    report = %{
      "stage" => "application_root",
      "boot_policy_selected_slot" => "A",
      "boot_policy_selection_reason" => "pending_attempt_limit",
      "boot_metadata_confirmed_slot" => "A",
      "boot_metadata_pending_slot" => "B"
    }

    assert FirmwareHealth.boot_action(report) == :reject_pending
  end

  test "does nothing for a confirmed boot" do
    report = %{
      "stage" => "application_root",
      "boot_policy_selected_slot" => "A",
      "boot_policy_selection_reason" => "confirmed",
      "boot_metadata_confirmed_slot" => "A",
      "boot_metadata_pending_slot" => "-"
    }

    assert FirmwareHealth.boot_action(report) == :none
  end
end

defmodule Atomcam2NervesApp.FirmwareUpdateTest do
  use ExUnit.Case, async: true

  test "exports the zero-arity SSH precheck callback" do
    Code.ensure_loaded!(Atomcam2NervesApp.FirmwareUpdate)

    assert function_exported?(Atomcam2NervesApp.FirmwareUpdate, :precheck, 0)
    refute function_exported?(Atomcam2NervesApp.FirmwareUpdate, :precheck, 2)
  end
end
