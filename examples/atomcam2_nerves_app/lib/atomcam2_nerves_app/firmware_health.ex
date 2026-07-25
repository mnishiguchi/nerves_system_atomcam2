defmodule Atomcam2NervesApp.FirmwareHealth do
  @moduledoc false

  use GenServer

  require Logger

  alias Nerves.Runtime.KV

  @boot_report "/media/mmc/atomcam2-boot-manager.env"
  @update_command "/usr/bin/atomcam2-firmware-update"
  @required_applications [:nerves_runtime, :vintage_net, :mdns_lite, :nerves_ssh]
  @firmware_product "atomcam2_nerves_app"
  @firmware_platform "atomcam2"
  @firmware_architecture "mipsel"
  @network_interface "wlan0"
  @firmware_uuid ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/

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

  @doc false
  def firmware_metadata_health(report, runtime) when is_map(report) and is_map(runtime) do
    selected_slot = Map.get(report, "boot_policy_selected_slot")
    slot_prefix = selected_slot |> to_string() |> String.downcase()

    with true <- selected_slot in ["A", "B"] || {:error, :selected_slot_invalid},
         "valid" <-
           Map.get(report, "boot_metadata_slot_#{slot_prefix}_status") ||
             {:error, :selected_slot_not_valid},
         firmware_id when is_binary(firmware_id) <-
           Map.get(report, "boot_metadata_slot_#{slot_prefix}_firmware_id") ||
             {:error, :selected_firmware_id_missing},
         true <-
           Regex.match?(@firmware_uuid, firmware_id) || {:error, :selected_firmware_id_invalid},
         ^slot_prefix <- Map.get(runtime, :active_slot) || {:error, :active_slot_mismatch},
         :unvalidated <-
           Map.get(runtime, :validation_status) ||
             {:error, :firmware_validation_status_mismatch},
         ^firmware_id <- Map.get(runtime, :firmware_uuid) || {:error, :firmware_uuid_mismatch},
         @firmware_product <-
           Map.get(runtime, :firmware_product) || {:error, :firmware_product_mismatch},
         @firmware_platform <-
           Map.get(runtime, :firmware_platform) || {:error, :firmware_platform_mismatch},
         @firmware_architecture <-
           Map.get(runtime, :firmware_architecture) ||
             {:error, :firmware_architecture_mismatch} do
      :ok
    else
      {:error, _reason} = error -> error
      _mismatch -> {:error, :firmware_metadata_mismatch}
    end
  end

  @doc false
  def network_interface_health(configuration, present, state) do
    cond do
      Map.get(configuration, :type) != VintageNetWiFi ->
        {:error, :wifi_configuration_missing}

      present != true ->
        {:error, :wifi_interface_not_present}

      state != :configured ->
        {:error, :wifi_interface_not_configured}

      true ->
        :ok
    end
  end

  defp check_firmware do
    with {:ok, contents} <- File.read(@boot_report) do
      report = parse_report(contents)
      perform_action(boot_action(report), report)
    else
      {:error, reason} ->
        Logger.warning("Firmware health check skipped: #{format_reason(reason)}")
    end
  end

  defp perform_action(:validate, report) do
    validate_pending_firmware(
      report,
      &local_health/1,
      &Nerves.Runtime.validate_firmware/0,
      &Nerves.Runtime.reboot/0
    )
  end

  defp perform_action(:reject_pending, _report) do
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

  defp perform_action(:none, _report), do: :ok

  @doc false
  def validate_pending_firmware(report, health_check, validate_firmware, reboot)
      when is_function(health_check, 1) and is_function(validate_firmware, 0) and
             is_function(reboot, 0) do
    case health_check.(report) do
      :ok ->
        case validate_firmware.() do
          :ok ->
            Logger.info("Pending Atom Cam 2 firmware confirmed")
            :ok

          {:error, reason} ->
            reboot_unhealthy("firmware confirmation failed", reason, reboot)
        end

      {:error, reason} ->
        reboot_unhealthy("local firmware health check failed", reason, reboot)
    end
  end

  defp local_health(report) do
    with :ok <- check_required_applications(),
         :ok <- check_data_writable(),
         :ok <- check_firmware_metadata(report),
         :ok <- check_network_interface(),
         :ok <- check_watchdog() do
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

  defp check_firmware_metadata(report) do
    slots = Nerves.Runtime.firmware_slots()

    firmware_metadata_health(report, %{
      active_slot: slots.active,
      validation_status: Nerves.Runtime.firmware_validation_status(),
      firmware_uuid: KV.get_active("nerves_fw_uuid"),
      firmware_product: KV.get_active("nerves_fw_product"),
      firmware_platform: KV.get_active("nerves_fw_platform"),
      firmware_architecture: KV.get_active("nerves_fw_architecture")
    })
  rescue
    exception -> {:error, {:firmware_metadata_unavailable, Exception.message(exception)}}
  end

  defp check_network_interface do
    configuration = VintageNet.get_configuration(@network_interface)
    present = VintageNet.get(["interface", @network_interface, "present"])
    state = VintageNet.get(["interface", @network_interface, "state"])

    network_interface_health(configuration, present, state)
  rescue
    exception -> {:error, {:network_interface_unavailable, Exception.message(exception)}}
  end

  defp check_watchdog do
    if Nerves.Runtime.Heart.running?() do
      :ok
    else
      {:error, :hardware_watchdog_not_running}
    end
  end

  defp reboot_unhealthy(message, reason, reboot) do
    Logger.error("#{message}: #{format_reason(reason)}; rebooting for rollback")
    reboot.()
  end

  defp stabilization_ms do
    Application.get_env(:atomcam2_nerves_app, :firmware_stabilization_ms, 30_000)
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end
