defmodule Atomcam2NervesApp.RtspServer do
  @moduledoc """
  Opt-in RTSP publishing for the vendor camera's encoded video.

  The vendor camera runtime is the only source of frames, so this server
  follows it: it starts once that runtime reports `running` and stops again
  when it does not. Failures stay visible without retry storms, matching the
  vendor camera integration.
  """

  use GenServer

  require Logger

  @command "/usr/bin/atomcam2-rtsp-server"
  @config_path "/data/atomcam2-rtsp/auto-start.conf"
  @poll_interval_ms 10_000
  @status_timeout_ms 45_000

  defstruct config_path: @config_path,
            poll_interval_ms: @poll_interval_ms,
            command_runner: nil,
            vendor_status: nil,
            timer_ref: nil,
            enabled: false,
            phase: :not_checked,
            last_checked_at: nil,
            last_result: :not_run,
            last_log_key: nil

  @type phase ::
          :not_checked
          | :disabled
          | :waiting
          | :running
          | :failed

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options \\ []) do
    name = Keyword.get(options, :name, __MODULE__)
    GenServer.start_link(__MODULE__, options, name: name)
  end

  @spec status(GenServer.server()) :: map()
  def status(server \\ __MODULE__) do
    GenServer.call(server, :status, @status_timeout_ms)
  end

  @spec run_now(GenServer.server()) :: :ok
  def run_now(server \\ __MODULE__) do
    GenServer.cast(server, :run_now)
  end

  @doc false
  @spec parse_config(String.t()) :: {:ok, boolean()} | {:error, :invalid_config}
  def parse_config(contents) do
    case contents do
      value when value in ["enabled=true", "enabled=true\n"] -> {:ok, true}
      value when value in ["enabled=false", "enabled=false\n"] -> {:ok, false}
      _other -> {:error, :invalid_config}
    end
  end

  @impl GenServer
  def init(options) do
    state = %__MODULE__{
      config_path: Keyword.get(options, :config_path, @config_path),
      poll_interval_ms: Keyword.get(options, :poll_interval_ms, @poll_interval_ms),
      command_runner: Keyword.get(options, :command_runner, &run_command/1),
      vendor_status: Keyword.get(options, :vendor_status, &vendor_status/0)
    }

    {:ok, schedule(state, 0)}
  end

  @impl GenServer
  def handle_call(:status, _from, state) do
    status =
      Map.take(state, [
        :config_path,
        :enabled,
        :phase,
        :last_checked_at,
        :last_result
      ])

    {:reply, status, state}
  end

  @impl GenServer
  def handle_cast(:run_now, state) do
    {:noreply, schedule(state, 0)}
  end

  @impl GenServer
  def handle_info(:poll, state) do
    state = %{state | timer_ref: nil}
    state = check(state)
    {:noreply, schedule(state, state.poll_interval_ms)}
  end

  defp check(state) do
    state = %{state | last_checked_at: DateTime.utc_now() |> DateTime.truncate(:second)}

    case read_config(state.config_path) do
      {:ok, false} ->
        state
        |> Map.put(:enabled, false)
        |> ensure_stopped(:disabled, "RTSP publishing is disabled")

      {:ok, true} ->
        check_enabled(%{state | enabled: true})

      {:error, :enoent} ->
        state
        |> Map.put(:enabled, false)
        |> ensure_stopped(:not_configured, "RTSP publishing is not configured")

      {:error, reason} ->
        state
        |> Map.put(:enabled, false)
        |> Map.put(:phase, :failed)
        |> Map.put(:last_result, {:configuration_error, reason})
        |> log_change(
          {:configuration_error, reason},
          :warning,
          "RTSP publishing configuration is invalid: #{inspect(reason)}"
        )
    end
  rescue
    exception ->
      reason = {exception.__struct__, Exception.message(exception)}

      state
      |> Map.put(:phase, :failed)
      |> Map.put(:last_result, {:unexpected_error, reason})
      |> log_change(
        {:unexpected_error, reason},
        :error,
        "RTSP publishing encountered an error: #{inspect(reason)}"
      )
  catch
    kind, reason ->
      failure = {kind, reason}

      state
      |> Map.put(:phase, :failed)
      |> Map.put(:last_result, {:unexpected_exit, failure})
      |> log_change(
        {:unexpected_exit, failure},
        :error,
        "RTSP publishing command exited: #{inspect(failure)}"
      )
  end

  defp check_enabled(state) do
    case {state.vendor_status.(), server_status(state.command_runner)} do
      {:running, :running} ->
        state
        |> Map.put(:phase, :running)
        |> Map.put(:last_result, :running)
        |> log_change(:running, :info, "RTSP publishing is running")

      {:running, :stopped} ->
        start_server(state)

      # Without the vendor runtime there are no frames, so a server left
      # behind would publish an empty stream and hold the loopback device.
      {vendor, :running} ->
        state
        |> ensure_stopped(
          {:vendor_not_running, vendor},
          "RTSP publishing stopped because the vendor camera runtime is #{inspect(vendor)}"
        )

      {vendor, :stopped} ->
        state
        |> Map.put(:phase, :waiting)
        |> Map.put(:last_result, {:waiting, vendor})
        |> log_change(
          {:waiting, vendor},
          :info,
          "RTSP publishing is waiting for the vendor camera runtime (#{inspect(vendor)})"
        )

      {_vendor, {:error, status}} ->
        state
        |> Map.put(:phase, :failed)
        |> Map.put(:last_result, {:status_failed, status})
        |> log_change(
          {:status_failed, status},
          :warning,
          "RTSP server status check failed: #{inspect(status)}"
        )
    end
  end

  defp start_server(state) do
    case state.command_runner.("start") do
      {output, 0} ->
        if line?(output, "result=running") do
          state
          |> Map.put(:phase, :running)
          |> Map.put(:last_result, :started)
          |> log_change(:started, :info, "RTSP publishing started")
        else
          start_failed(state, {:verification_failed, output})
        end

      {output, status} ->
        start_failed(state, {:command_failed, status, reason(output)})
    end
  end

  defp start_failed(state, failure) do
    state
    |> Map.put(:phase, :failed)
    |> Map.put(:last_result, {:start_failed, failure})
    |> log_change(
      {:start_failed, failure},
      :error,
      "RTSP publishing failed to start: #{inspect(failure)}"
    )
  end

  defp ensure_stopped(state, key, message) do
    case server_status(state.command_runner) do
      :running ->
        _ = state.command_runner.("stop")

        state
        |> Map.put(:phase, :disabled)
        |> Map.put(:last_result, key)
        |> log_change(key, :info, message)

      _other ->
        state
        |> Map.put(:phase, :disabled)
        |> Map.put(:last_result, key)
        |> log_change(key, :info, message)
    end
  end

  defp server_status(command_runner) do
    case command_runner.("status") do
      {output, 0} ->
        cond do
          line?(output, "result=running") -> :running
          line?(output, "result=stopped") -> :stopped
          true -> {:error, :unknown_status}
        end

      {_output, status} ->
        {:error, status}
    end
  end

  defp vendor_status do
    case Atomcam2NervesApp.VendorCamera.status() do
      %{phase: :running} -> :running
      %{phase: phase} -> phase
    end
  catch
    :exit, _reason -> :unavailable
  end

  defp reason(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.find_value(:unknown, fn line ->
      case String.split(line, "=", parts: 2) do
        ["reason", value] -> value
        _other -> nil
      end
    end)
  end

  defp line?(output, expected) do
    output
    |> String.split("\n", trim: true)
    |> Enum.member?(expected)
  end

  defp read_config(path) do
    with {:ok, contents} <- File.read(path) do
      parse_config(contents)
    end
  end

  defp run_command(action) do
    System.cmd(@command, [action], stderr_to_stdout: true)
  end

  defp schedule(%{timer_ref: timer_ref} = state, interval_ms) do
    if is_reference(timer_ref) do
      Process.cancel_timer(timer_ref)
    end

    %{state | timer_ref: Process.send_after(self(), :poll, interval_ms)}
  end

  defp log_change(%{last_log_key: key} = state, key, _level, _message), do: state

  defp log_change(state, key, level, message) do
    Logger.log(level, message)
    %{state | last_log_key: key}
  end
end
