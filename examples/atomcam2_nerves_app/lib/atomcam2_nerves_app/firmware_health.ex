defmodule Atomcam2NervesApp.FirmwareHealth do
  @moduledoc false

  use GenServer

  require Logger

  @boot_report "/media/mmc/atomcam2-boot-manager.env"
  @update_command "/usr/bin/atomcam2-firmware-update"
  @required_applications [:nerves_runtime, :vintage_net, :mdns_lite, :nerves_ssh]

  def child_spec(args) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [args]},
      restart: :transient
    }
  end

  def start_link(_args) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl GenServer
  def init(nil) do
    Process.send_after(self(), :check_firmware, stabilization_ms())
    {:ok, nil}
  end

  @impl GenServer
  def handle_info(:check_firmware, state) do
    check_firmware()
    {:stop, :normal, state}
  end

  @doc false
  def parse_report(contents) when is_binary(contents) do
    contents
    |> String.split("\n", trim: true)
    |> Enum.reduce(%{}, fn line, report ->
      case String.split(line, "=", parts: 2) do
        [key, value] -> Map.put(report, key, value)
        _other -> report
      end
    end)
  end

  @doc false
  def boot_action(report) when is_map(report) do
    selected_slot = Map.get(report, "boot_policy_selected_slot")
    selection_reason = Map.get(report, "boot_policy_selection_reason")
    confirmed_slot = Map.get(report, "boot_metadata_confirmed_slot")
    pending_slot = Map.get(report, "boot_metadata_pending_slot")

    cond do
      Map.get(report, "stage") != "application_root" ->
        :none

      selection_reason == "pending" and pending_slot in ["A", "B"] and
          selected_slot == pending_slot ->
        :validate

      selection_reason == "pending_attempt_limit" and pending_slot in ["A", "B"] and
          selected_slot == confirmed_slot ->
        :reject_pending

      true ->
        :none
    end
  end

  defp check_firmware do
    with {:ok, contents} <- File.read(@boot_report) do
      contents
      |> parse_report()
      |> boot_action()
      |> perform_action()
    else
      {:error, reason} ->
        Logger.warning("Firmware health check skipped: #{format_reason(reason)}")
    end
  end

  defp perform_action(:validate) do
    case local_health() do
      :ok ->
        case Nerves.Runtime.validate_firmware() do
          :ok ->
            Logger.info("Pending Atom Cam 2 firmware confirmed")

          {:error, reason} ->
            reboot_unhealthy("firmware confirmation failed", reason)
        end

      {:error, reason} ->
        reboot_unhealthy("local firmware health check failed", reason)
    end
  end

  defp perform_action(:reject_pending) do
    case System.cmd(@update_command, ["reject-pending"], stderr_to_stdout: true) do
      {_output, 0} ->
        Logger.warning("Rejected Atom Cam 2 firmware after exhausting pending boot attempts")

      {output, status} ->
        Logger.error(
          "Could not reject exhausted pending firmware with status #{status}: " <>
            String.trim(output)
        )
    end
  rescue
    exception ->
      Logger.error("Could not reject exhausted pending firmware: #{Exception.message(exception)}")
  end

  defp perform_action(:none), do: :ok

  defp local_health do
    with :ok <- check_required_applications(),
         :ok <- check_data_writable() do
      :ok
    end
  end

  defp check_required_applications do
    started_applications =
      Application.started_applications()
      |> Enum.map(fn {application, _description, _version} -> application end)
      |> MapSet.new()

    missing_applications =
      Enum.reject(@required_applications, &MapSet.member?(started_applications, &1))

    case missing_applications do
      [] -> :ok
      missing -> {:error, {:applications_not_started, missing}}
    end
  end

  defp check_data_writable do
    probe_path = "/data/.atomcam2-firmware-health"

    with :ok <- File.write(probe_path, "healthy\n"),
         :ok <- File.rm(probe_path) do
      :ok
    end
  end

  defp reboot_unhealthy(message, reason) do
    Logger.error("#{message}: #{format_reason(reason)}; rebooting for rollback")
    Nerves.Runtime.reboot()
  end

  defp stabilization_ms do
    Application.get_env(:atomcam2_nerves_app, :firmware_stabilization_ms, 30_000)
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end
