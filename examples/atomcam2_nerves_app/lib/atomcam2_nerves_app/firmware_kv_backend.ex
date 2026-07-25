defmodule Atomcam2NervesApp.FirmwareKVBackend do
  @moduledoc false

  if Code.ensure_loaded?(Nerves.Runtime.KVBackend) do
    @behaviour Nerves.Runtime.KVBackend
  end

  @boot_report "/media/mmc/atomcam2-boot-manager.env"
  @metadata_command "/usr/bin/atomcam2-boot-metadata"
  @root_disk "/dev/rootdisk0"
  @uuid_regex ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/

  def load(options) do
    contents = Keyword.fetch!(options, :contents)
    boot_report = read_boot_report(options)
    live_metadata = read_live_metadata(options) || boot_report

    {:ok, contents_from_reports(contents, boot_report, live_metadata)}
  end

  def save(_contents, _options), do: :ok

  @doc false
  def contents_from_reports(contents, boot_report, live_metadata)
      when is_map(contents) and is_binary(boot_report) and is_binary(live_metadata) do
    boot_report = parse_report(boot_report)
    live_metadata = parse_report(live_metadata)
    active = boot_report |> Map.get("boot_policy_selected_slot") |> slot_name("a")
    confirmed = metadata_value(live_metadata, boot_report, "confirmed_slot")
    pending = metadata_value(live_metadata, boot_report, "pending_slot")

    Enum.reduce(["a", "b"], Map.put(contents, "nerves_fw_active", active), fn slot, acc ->
      put_slot_metadata(acc, slot, confirmed, pending, live_metadata, boot_report)
    end)
  end

  defp read_boot_report(options) do
    case Keyword.fetch(options, :boot_report_contents) do
      {:ok, contents} ->
        contents

      :error ->
        options
        |> Keyword.get(:boot_report, @boot_report)
        |> File.read()
        |> case do
          {:ok, contents} -> contents
          {:error, _reason} -> ""
        end
    end
  end

  defp read_live_metadata(options) do
    case Keyword.fetch(options, :metadata_contents) do
      {:ok, contents} ->
        contents

      :error ->
        run_metadata_command(options)
    end
  end

  defp run_metadata_command(options) do
    command = Keyword.get(options, :metadata_command, @metadata_command)
    root_disk = Keyword.get(options, :root_disk, @root_disk)

    work_directory =
      Path.join(
        System.tmp_dir!(),
        "atomcam2-kv-#{System.unique_integer([:positive, :monotonic])}"
      )

    try do
      case System.cmd(command, ["select-device", root_disk, work_directory],
             stderr_to_stdout: true
           ) do
        {contents, 0} -> contents
        {_output, _status} -> nil
      end
    rescue
      _exception -> nil
    after
      File.rm_rf(work_directory)
    end
  end

  defp parse_report(contents) do
    contents
    |> String.split("\n", trim: true)
    |> Enum.reduce(%{}, fn line, report ->
      case String.split(String.trim_trailing(line, "\r"), "=", parts: 2) do
        [key, value] -> Map.put(report, key, value)
        _other -> report
      end
    end)
  end

  defp put_slot_metadata(contents, slot, confirmed, pending, live_metadata, boot_report) do
    firmware_id = metadata_value(live_metadata, boot_report, "slot_#{slot}_firmware_id")
    status = metadata_value(live_metadata, boot_report, "slot_#{slot}_status")
    metadata_slot = String.upcase(slot)

    if is_binary(firmware_id) and Regex.match?(@uuid_regex, firmware_id) do
      contents
      |> Map.put("#{slot}.nerves_fw_uuid", firmware_id)
      |> Map.put(
        "#{slot}.nerves_fw_validated",
        validation_value(metadata_slot, confirmed, pending, status)
      )
    else
      contents
      |> Map.delete("#{slot}.nerves_fw_uuid")
      |> Map.delete("#{slot}.nerves_fw_validated")
    end
  end

  defp validation_value(slot, _confirmed, slot, _status), do: "0"
  defp validation_value(slot, slot, _pending, "valid"), do: "1"
  defp validation_value(_slot, _confirmed, _pending, "valid"), do: "1"
  defp validation_value(_slot, _confirmed, _pending, _status), do: "0"

  defp metadata_value(live_metadata, boot_report, key) do
    Map.get(live_metadata, key) || Map.get(boot_report, "boot_metadata_#{key}")
  end

  defp slot_name("A", _fallback), do: "a"
  defp slot_name("B", _fallback), do: "b"
  defp slot_name(_slot, fallback), do: fallback
end
