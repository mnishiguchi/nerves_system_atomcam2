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

  test "accepts matching pending firmware metadata" do
    firmware_uuid = "22222222-2222-4222-8222-222222222222"

    report = %{
      "boot_policy_selected_slot" => "B",
      "boot_metadata_slot_b_status" => "valid",
      "boot_metadata_slot_b_firmware_id" => firmware_uuid
    }

    runtime = %{
      active_slot: "b",
      validation_status: :unvalidated,
      firmware_uuid: firmware_uuid,
      firmware_product: "atomcam2_nerves_app",
      firmware_platform: "atomcam2",
      firmware_architecture: "mipsel"
    }

    assert FirmwareHealth.firmware_metadata_health(report, runtime) == :ok
  end

  test "rejects firmware metadata when the running UUID does not match the selected slot" do
    report = %{
      "boot_policy_selected_slot" => "B",
      "boot_metadata_slot_b_status" => "valid",
      "boot_metadata_slot_b_firmware_id" => "22222222-2222-4222-8222-222222222222"
    }

    runtime = %{
      active_slot: "b",
      validation_status: :unvalidated,
      firmware_uuid: "33333333-3333-4333-8333-333333333333",
      firmware_product: "atomcam2_nerves_app",
      firmware_platform: "atomcam2",
      firmware_architecture: "mipsel"
    }

    assert FirmwareHealth.firmware_metadata_health(report, runtime) ==
             {:error, :firmware_metadata_mismatch}
  end

  test "rejects firmware metadata that is already validated" do
    firmware_uuid = "22222222-2222-4222-8222-222222222222"

    report = %{
      "boot_policy_selected_slot" => "B",
      "boot_metadata_slot_b_status" => "valid",
      "boot_metadata_slot_b_firmware_id" => firmware_uuid
    }

    runtime = %{
      active_slot: "b",
      validation_status: :validated,
      firmware_uuid: firmware_uuid,
      firmware_product: "atomcam2_nerves_app",
      firmware_platform: "atomcam2",
      firmware_architecture: "mipsel"
    }

    assert FirmwareHealth.firmware_metadata_health(report, runtime) ==
             {:error, :firmware_metadata_mismatch}
  end

  test "accepts configured WiFi without requiring connectivity" do
    configuration = %{type: VintageNetWiFi}

    assert FirmwareHealth.network_interface_health(configuration, true, :configured) == :ok
  end

  test "rejects absent or unconfigured WiFi" do
    configuration = %{type: VintageNetWiFi}

    assert FirmwareHealth.network_interface_health(configuration, false, :configured) ==
             {:error, :wifi_interface_not_present}

    assert FirmwareHealth.network_interface_health(configuration, true, :disconnected) ==
             {:error, :wifi_interface_not_configured}
  end

  test "reboots without confirming when a local health check fails" do
    test_process = self()
    report = %{"boot_policy_selected_slot" => "B"}

    health_check = fn received_report ->
      send(test_process, {:health_checked, received_report})
      {:error, :wifi_interface_not_configured}
    end

    validate_firmware = fn ->
      send(test_process, :firmware_confirmed)
      :ok
    end

    reboot = fn ->
      send(test_process, :rebooted)
      :rebooted
    end

    assert FirmwareHealth.validate_pending_firmware(
             report,
             health_check,
             validate_firmware,
             reboot
           ) == :rebooted

    assert_received {:health_checked, ^report}
    assert_received :rebooted
    refute_received :firmware_confirmed
  end

  test "reboots when pending firmware confirmation fails" do
    test_process = self()

    validate_firmware = fn ->
      send(test_process, :confirmation_attempted)
      {:error, :metadata_write_failed}
    end

    reboot = fn ->
      send(test_process, :rebooted)
      :rebooted
    end

    assert FirmwareHealth.validate_pending_firmware(
             %{},
             fn _report -> :ok end,
             validate_firmware,
             reboot
           ) == :rebooted

    assert_received :confirmation_attempted
    assert_received :rebooted
  end

  test "does not reboot after successful pending firmware confirmation" do
    test_process = self()

    reboot = fn ->
      send(test_process, :rebooted)
      :rebooted
    end

    assert FirmwareHealth.validate_pending_firmware(
             %{},
             fn _report -> :ok end,
             fn -> :ok end,
             reboot
           ) == :ok

    refute_received :rebooted
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
