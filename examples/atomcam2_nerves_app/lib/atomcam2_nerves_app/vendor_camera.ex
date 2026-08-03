defmodule Atomcam2NervesApp.VendorCamera do
  @moduledoc """
  Opt-in boot integration for the vendor camera compatibility runtime.

  Automatic startup is deliberately conservative. It makes one start attempt
  per boot after firmware, network, and time readiness checks pass. Runtime
  failures remain visible for an operator and never trigger a reboot loop.
  """

  use GenServer

  require Logger

  @compile {:no_warn_undefined, Nerves.Runtime}
  @compile {:no_warn_undefined, VintageNet}

  @command "/usr/bin/atomcam2-vendor-camera"
  @config_path "/data/atomcam2-vendor-camera/auto-start.conf"
  @poll_interval_ms 10_000
  @max_start_attempts 1
  @status_timeout_ms 45_000
  # The overall connection status across every interface, so a wired-only
  # deployment (USB Ethernet, no wlan0 association) is considered connected.
  @connection_property ["connection"]

  defstruct config_path: @config_path,
            poll_interval_ms: @poll_interval_ms,
            command_runner: nil,
            readiness: nil,
            timer_ref: nil,
            enabled: false,
            phase: :not_checked,
            start_attempts: 0,
            last_checked_at: nil,
            last_result: :not_run,
            last_log_key: nil

  @type phase ::
          :not_checked
          | :disabled
          | :waiting
          | :starting
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
      readiness: Keyword.get(options, :readiness, &readiness/0)
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
        :start_attempts,
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
        |> Map.put(:phase, :disabled)
        |> Map.put(:last_result, :disabled)
        |> log_change(:disabled, :info, "Vendor camera automatic startup is disabled")

      {:ok, true} ->
        check_enabled(%{state | enabled: true})

      {:error, :enoent} ->
        state
        |> Map.put(:enabled, false)
        |> Map.put(:phase, :disabled)
        |> Map.put(:last_result, :not_configured)
        |> log_change(
          :not_configured,
          :info,
          "Vendor camera automatic startup is not configured"
        )

      {:error, reason} ->
        state
        |> Map.put(:enabled, false)
        |> Map.put(:phase, :failed)
        |> Map.put(:last_result, {:configuration_error, reason})
        |> log_change(
          {:configuration_error, reason},
          :warning,
          "Vendor camera automatic startup configuration is invalid: #{inspect(reason)}"
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
        "Vendor camera automatic startup encountered an error: #{inspect(reason)}"
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
        "Vendor camera automatic startup command exited: #{inspect(failure)}"
      )
  end

  defp check_enabled(state) do
    case runtime_status(state.command_runner) do
      :running ->
        state
        |> Map.put(:phase, :running)
        |> Map.put(:last_result, :running)
        |> log_change(:running, :info, "Vendor camera compatibility runtime is running")

      :stopped when state.start_attempts < @max_start_attempts ->
        maybe_start(state)

      :stopped ->
        state
        |> Map.put(:phase, :failed)
        |> Map.put(:last_result, :start_attempt_limit)
        |> log_change(
          :start_attempt_limit,
          :warning,
          "Vendor camera automatic start attempt limit reached"
        )

      :stopped_reboot_required ->
        state
        |> Map.put(:phase, :failed)
        |> Map.put(:last_result, :reboot_required)
        |> log_change(
          :reboot_required,
          :warning,
          "Vendor camera runtime requires a deliberate reboot before another start"
        )

      {:degraded, status} ->
        state
        |> Map.put(:phase, :failed)
        |> Map.put(:last_result, {:runtime_degraded, status})
        |> log_change(
          {:runtime_degraded, status},
          :error,
          "Vendor camera runtime is degraded; automatic restart is disabled"
        )

      {:error, status} ->
        state
        |> Map.put(:phase, :failed)
        |> Map.put(:last_result, {:status_failed, status})
        |> log_change(
          {:status_failed, status},
          :warning,
          "Vendor camera runtime status check failed: #{inspect(status)}"
        )
    end
  end

  defp maybe_start(state) do
    case state.readiness.() do
      :ready ->
        start_runtime(state)

      {:waiting, reasons} ->
        state
        |> Map.put(:phase, :waiting)
        |> Map.put(:last_result, {:waiting, reasons})
        |> log_change(
          {:waiting, reasons},
          :info,
          "Vendor camera automatic startup is waiting for #{format_reasons(reasons)}"
        )
    end
  end

  defp start_runtime(state) do
    state = %{state | phase: :starting, start_attempts: state.start_attempts + 1}

    with {_, 0} <- state.command_runner.("precheck"),
         {_, 0} <- state.command_runner.("start"),
         :running <- runtime_status(state.command_runner) do
      state
      |> Map.put(:phase, :running)
      |> Map.put(:last_result, :started)
      |> log_change(:started, :info, "Vendor camera compatibility runtime started automatically")
    else
      {_, status} ->
        start_failed(state, {:command_failed, status})

      runtime_state ->
        start_failed(state, {:verification_failed, runtime_state})
    end
  end

  defp start_failed(state, reason) do
    state
    |> Map.put(:phase, :failed)
    |> Map.put(:last_result, {:start_failed, reason})
    |> log_change(
      {:start_failed, reason},
      :error,
      "Vendor camera automatic startup failed: #{inspect(reason)}"
    )
  end

  defp runtime_status(command_runner) do
    case command_runner.("status") do
      {output, 0} ->
        cond do
          line?(output, "result=running") -> :running
          line?(output, "result=stopped_reboot_required") -> :stopped_reboot_required
          line?(output, "result=stopped") -> :stopped
          true -> {:error, :unknown_status}
        end

      {output, status} ->
        if line?(output, "result=degraded") do
          {:degraded, status}
        else
          {:error, status}
        end
    end
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

  defp readiness do
    reasons =
      []
      |> maybe_add(
        Nerves.Runtime.firmware_validation_status() != :validated,
        :validated_firmware
      )
      |> maybe_add(
        VintageNet.get(@connection_property) != :internet,
        :internet_connection
      )
      |> maybe_add(not NervesTime.synchronized?(), :synchronized_time)

    if reasons == [], do: :ready, else: {:waiting, reasons}
  end

  defp maybe_add(reasons, true, reason), do: reasons ++ [reason]
  defp maybe_add(reasons, false, _reason), do: reasons

  defp run_command(action) do
    # MuonTrap's port helper exits with :epipe on the protected 3.10 kernel.
    # These are fixed, local compatibility-script actions with bounded work.
    System.cmd(
      @command,
      [action],
      stderr_to_stdout: true
    )
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

  defp format_reasons(reasons) do
    Enum.map_join(reasons, ", ", &Atom.to_string/1)
  end
end
