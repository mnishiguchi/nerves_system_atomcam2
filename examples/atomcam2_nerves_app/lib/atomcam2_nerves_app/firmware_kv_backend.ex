defmodule Atomcam2NervesApp.FirmwareKVBackend do
  @moduledoc false

  if Code.ensure_loaded?(Nerves.Runtime.KVBackend) do
    @behaviour Nerves.Runtime.KVBackend
  end

  @boot_report "/media/mmc/atomcam2-boot-manager.env"

  def load(options) do
    contents = Keyword.fetch!(options, :contents)
    {:ok, Map.put(contents, "nerves_fw_active", active_partition())}
  end

  def save(_contents, _options), do: :ok

  @doc false
  def active_partition do
    case File.read(@boot_report) do
      {:ok, contents} -> active_partition_from_report(contents)
      {:error, _reason} -> "a"
    end
  end

  @doc false
  def active_partition_from_report(contents) when is_binary(contents) do
    contents
    |> String.split("\n", trim: true)
    |> Enum.find_value("a", fn line ->
      case String.split(line, "=", parts: 2) do
        ["boot_policy_selected_slot", "A"] -> "a"
        ["boot_policy_selected_slot", "B"] -> "b"
        _other -> nil
      end
    end)
  end
end
