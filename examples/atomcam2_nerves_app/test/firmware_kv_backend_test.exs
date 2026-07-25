defmodule Atomcam2NervesApp.FirmwareKVBackendTest do
  use ExUnit.Case, async: true

  alias Atomcam2NervesApp.FirmwareKVBackend

  test "maps live slot UUIDs and validation state to standard Nerves keys" do
    boot_report = """
    stage=application_root
    boot_policy_selected_slot=B
    boot_policy_selection_reason=pending
    boot_metadata_confirmed_slot=A
    boot_metadata_pending_slot=B
    """

    live_metadata = """
    selected_slot=B
    confirmed_slot=A
    pending_slot=B
    slot_a_status=valid
    slot_a_firmware_id=11111111-1111-4111-8111-111111111111
    slot_b_status=valid
    slot_b_firmware_id=22222222-2222-4222-8222-222222222222
    """

    contents =
      FirmwareKVBackend.contents_from_reports(%{}, boot_report, live_metadata)

    assert contents["nerves_fw_active"] == "b"
    assert contents["a.nerves_fw_uuid"] == "11111111-1111-4111-8111-111111111111"
    assert contents["a.nerves_fw_validated"] == "1"
    assert contents["b.nerves_fw_uuid"] == "22222222-2222-4222-8222-222222222222"
    assert contents["b.nerves_fw_validated"] == "0"
  end

  test "uses live confirmation state instead of the stale boot report" do
    boot_report = """
    boot_policy_selected_slot=B
    boot_metadata_confirmed_slot=A
    boot_metadata_pending_slot=B
    boot_metadata_slot_b_status=valid
    boot_metadata_slot_b_firmware_id=22222222-2222-4222-8222-222222222222
    """

    live_metadata = """
    confirmed_slot=B
    pending_slot=-
    slot_b_status=valid
    slot_b_firmware_id=22222222-2222-4222-8222-222222222222
    """

    contents =
      FirmwareKVBackend.contents_from_reports(%{}, boot_report, live_metadata)

    assert contents["nerves_fw_active"] == "b"
    assert contents["b.nerves_fw_validated"] == "1"
  end

  test "falls back to boot metadata and ignores malformed UUIDs" do
    boot_report = """
    boot_policy_selected_slot=A
    boot_metadata_confirmed_slot=A
    boot_metadata_pending_slot=-
    boot_metadata_slot_a_status=valid
    boot_metadata_slot_a_firmware_id=11111111-1111-4111-8111-111111111111
    boot_metadata_slot_b_status=empty
    boot_metadata_slot_b_firmware_id=not-a-uuid
    """

    contents =
      FirmwareKVBackend.contents_from_reports(
        %{"b.nerves_fw_uuid" => "stale"},
        boot_report,
        boot_report
      )

    assert contents["a.nerves_fw_uuid"] == "11111111-1111-4111-8111-111111111111"
    assert contents["a.nerves_fw_validated"] == "1"
    refute Map.has_key?(contents, "b.nerves_fw_uuid")
    refute Map.has_key?(contents, "b.nerves_fw_validated")
  end

  test "load accepts report contents for deterministic backend tests" do
    report = """
    boot_policy_selected_slot=A
    boot_metadata_confirmed_slot=A
    boot_metadata_pending_slot=-
    boot_metadata_slot_a_status=valid
    boot_metadata_slot_a_firmware_id=11111111-1111-4111-8111-111111111111
    """

    assert {:ok, contents} =
             FirmwareKVBackend.load(
               contents: %{"a.nerves_fw_product" => "camera"},
               boot_report_contents: report,
               metadata_contents: report
             )

    assert contents["a.nerves_fw_product"] == "camera"
    assert contents["a.nerves_fw_uuid"] == "11111111-1111-4111-8111-111111111111"
  end
end
