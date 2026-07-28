defmodule Atomcam2NervesApp.NasExporter do
  @moduledoc """
  Exports finalized vendor recordings from the local spool to a NAS.

  The exporter remains dormant unless its persistent configuration explicitly
  enables it.
  """

  use GenServer

  require Logger

  alias Atomcam2NervesApp.NasExporter.Config
  alias Atomcam2NervesApp.NasExporter.SFTP

  @default_config_path "/data/atomcam2-vendor-camera/nas-export.conf"
  @default_spool_path "/data/atomcam2-vendor-camera/spool/record"
  @default_marker_path "/data/atomcam2-vendor-camera/nas-exported"
  @default_poll_interval_ms 60_000
  @max_files_per_run 2

  defstruct config_path: @default_config_path,
            spool_path: @default_spool_path,
            marker_path: @default_marker_path,
            transport: SFTP,
            timer_ref: nil,
            enabled: false,
            last_attempt_at: nil,
            last_result: :not_run,
            last_log_key: nil

  @type completed_file :: %{
          path: Path.t(),
          relative_path: String.t(),
          size: non_neg_integer()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options \\ []) do
    name = Keyword.get(options, :name, __MODULE__)
    GenServer.start_link(__MODULE__, options, name: name)
  end

  @spec status(GenServer.server()) :: map()
  def status(server \\ __MODULE__) do
    GenServer.call(server, :status)
  end

  @spec run_now(GenServer.server()) :: :ok
  def run_now(server \\ __MODULE__) do
    GenServer.cast(server, :run_now)
  end

  @impl GenServer
  def init(options) do
    state = %__MODULE__{
      config_path: Keyword.get(options, :config_path, @default_config_path),
      spool_path: Keyword.get(options, :spool_path, @default_spool_path),
      marker_path: Keyword.get(options, :marker_path, @default_marker_path),
      transport: Keyword.get(options, :transport, SFTP)
    }

    {:ok, schedule(state, 0)}
  end

  @impl GenServer
  def handle_call(:status, _from, state) do
    status =
      Map.take(state, [
        :config_path,
        :spool_path,
        :marker_path,
        :enabled,
        :last_attempt_at,
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
    {state, interval_ms} = run_once(state)
    {:noreply, schedule(state, interval_ms)}
  end

  @doc false
  @spec completed_files(Path.t()) :: [completed_file()]
  def completed_files(spool_path) do
    spool_path
    |> Path.join("**/*.mp4")
    |> Path.wildcard(match_dot: false)
    |> Enum.flat_map(&completed_file(&1, spool_path))
    |> Enum.sort_by(& &1.relative_path)
  end

  @doc false
  @spec enforce_spool_limit([completed_file()], non_neg_integer(), Path.t() | nil) :: map()
  def enforce_spool_limit(files, max_bytes, marker_path \\ nil) do
    total_bytes = Enum.reduce(files, 0, &(&1.size + &2))

    if total_bytes <= max_bytes do
      %{deleted_count: 0, deleted_bytes: 0, remaining_bytes: total_bytes}
    else
      removable_files =
        if marker_path do
          Enum.filter(files, &exported?(&1, marker_path))
        else
          files
        end

      trim_spool(removable_files, total_bytes, max_bytes, marker_path, 0, 0)
    end
  end

  defp run_once(state) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    state = %{state | last_attempt_at: now}

    case Config.load(state.config_path) do
      {:ok, %Config{enabled: false} = config} ->
        disconnect_transport(state.transport)

        state =
          state
          |> Map.put(:enabled, false)
          |> Map.put(:last_result, :disabled)
          |> log_change(:disabled, :info, "NAS exporter is disabled")

        {state, config.poll_interval_ms}

      {:ok, %Config{enabled: true} = config} ->
        run_enabled(state, config)

      {:error, :enoent} ->
        disconnect_transport(state.transport)

        state =
          state
          |> Map.put(:enabled, false)
          |> Map.put(:last_result, :not_configured)
          |> log_change(:not_configured, :info, "NAS exporter is not configured")

        {state, @default_poll_interval_ms}

      {:error, reason} ->
        disconnect_transport(state.transport)

        state =
          state
          |> Map.put(:enabled, false)
          |> Map.put(:last_result, {:configuration_error, reason})
          |> log_change(
            {:configuration_error, reason},
            :warning,
            "NAS exporter configuration is invalid: #{inspect(reason)}"
          )

        {state, @default_poll_interval_ms}
    end
  rescue
    exception ->
      disconnect_transport(state.transport)
      reason = {exception.__struct__, Exception.message(exception)}

      state =
        state
        |> Map.put(:last_result, {:unexpected_error, reason})
        |> log_change(
          {:unexpected_error, reason},
          :error,
          "NAS exporter encountered an unexpected error: #{inspect(reason)}"
        )

      {state, @default_poll_interval_ms}
  end

  defp run_enabled(state, config) do
    files = completed_files(state.spool_path)

    batch =
      files
      |> Stream.reject(&exported?(&1, state.marker_path))
      |> Enum.take(@max_files_per_run)

    case invoke_transport(state.transport, config, batch) do
      {:ok, summary} ->
        case mark_completed(summary, state.marker_path) do
          {:ok, summary} ->
            handle_export_success(state, config, files, summary)

          {:error, reason, summary} ->
            handle_export_error(
              state,
              config,
              files,
              {:marker_write_failed, reason},
              summary
            )
        end

      {:error, reason, summary} ->
        case mark_completed(summary, state.marker_path) do
          {:ok, summary} ->
            handle_export_error(state, config, files, reason, summary)

          {:error, marker_reason, summary} ->
            handle_export_error(
              state,
              config,
              files,
              {reason, {:marker_write_failed, marker_reason}},
              summary
            )
        end
    end
  end

  defp invoke_transport(transport, config, files) do
    transport.export(config, files)
  rescue
    exception ->
      reason = {exception.__struct__, Exception.message(exception)}
      {:error, {:transport_exception, reason}, empty_summary()}
  catch
    kind, reason ->
      {:error, {:transport_failure, kind, reason}, empty_summary()}
  end

  defp disconnect_transport(transport) do
    if function_exported?(transport, :disconnect, 0) do
      transport.disconnect()
    end

    :ok
  rescue
    exception ->
      Logger.warning(
        "NAS transport disconnect failed: " <>
          Exception.format(:error, exception, __STACKTRACE__)
      )

      :ok
  catch
    kind, reason ->
      Logger.warning("NAS transport disconnect failed: #{inspect({kind, reason})}")
      :ok
  end

  defp empty_summary do
    %{uploaded: 0, already_present: 0, retained_removed: 0, completed_files: []}
  end

  defp handle_export_success(state, config, files, summary) do
    spool = enforce_configured_spool_limit(files, state, config)
    result = {:ok, Map.put(summary, :spool, spool)}

    state =
      state
      |> Map.put(:enabled, true)
      |> Map.put(:last_result, result)
      |> log_change(
        result_log_key(result),
        :info,
        success_message(summary, spool)
      )

    {state, config.poll_interval_ms}
  end

  defp handle_export_error(state, config, files, reason, summary) do
    spool = enforce_configured_spool_limit(files, state, config)
    result = {:error, reason, Map.put(summary, :spool, spool)}

    state =
      state
      |> Map.put(:enabled, true)
      |> Map.put(:last_result, result)
      |> log_change(
        {:export_error, reason},
        :warning,
        "NAS export will retry: #{inspect(reason)}; " <> spool_message(spool)
      )

    {state, config.poll_interval_ms}
  end

  defp enforce_configured_spool_limit(files, state, config) do
    enforce_spool_limit(files, config.max_spool_bytes, state.marker_path)
  end

  defp completed_file(path, spool_path) do
    relative_path = Path.relative_to(path, spool_path)

    with true <- String.match?(relative_path, ~r/\A\d{8}\/\d{2}\/\d{2}\.mp4\z/),
         {:ok, %File.Stat{type: :regular, size: size}} <- File.lstat(path) do
      [%{path: path, relative_path: relative_path, size: size}]
    else
      _other -> []
    end
  end

  defp exported?(file, marker_path) do
    case File.read(marker_file(marker_path, file.relative_path)) do
      {:ok, contents} -> String.trim(contents) == Integer.to_string(file.size)
      {:error, _reason} -> false
    end
  end

  defp mark_completed(summary, marker_path) do
    completed_files = Map.fetch!(summary, :completed_files)
    public_summary = Map.delete(summary, :completed_files)

    Enum.reduce_while(completed_files, {:ok, public_summary}, fn file, {:ok, summary} ->
      case write_marker(marker_path, file) do
        :ok -> {:cont, {:ok, summary}}
        {:error, reason} -> {:halt, {:error, {file.relative_path, reason}, summary}}
      end
    end)
  end

  defp write_marker(marker_path, file) do
    path = marker_file(marker_path, file.relative_path)
    temporary_path = path <> ".tmp"

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(temporary_path, "#{file.size}\n"),
         :ok <- File.rename(temporary_path, path) do
      :ok
    end
  end

  defp marker_file(marker_path, relative_path), do: Path.join(marker_path, relative_path)

  defp trim_spool(
         [],
         remaining_bytes,
         _max_bytes,
         _marker_path,
         deleted_count,
         deleted_bytes
       ) do
    %{
      deleted_count: deleted_count,
      deleted_bytes: deleted_bytes,
      remaining_bytes: remaining_bytes
    }
  end

  defp trim_spool(
         _files,
         remaining_bytes,
         max_bytes,
         _marker_path,
         deleted_count,
         deleted_bytes
       )
       when remaining_bytes <= max_bytes do
    %{
      deleted_count: deleted_count,
      deleted_bytes: deleted_bytes,
      remaining_bytes: remaining_bytes
    }
  end

  defp trim_spool(
         [file | rest],
         remaining_bytes,
         max_bytes,
         marker_path,
         deleted_count,
         deleted_bytes
       ) do
    case File.rm(file.path) do
      :ok ->
        if marker_path do
          _result = File.rm(marker_file(marker_path, file.relative_path))
        end

        trim_spool(
          rest,
          remaining_bytes - file.size,
          max_bytes,
          marker_path,
          deleted_count + 1,
          deleted_bytes + file.size
        )

      {:error, reason} ->
        Logger.warning("NAS spool could not remove #{file.relative_path}: #{inspect(reason)}")

        trim_spool(
          rest,
          remaining_bytes,
          max_bytes,
          marker_path,
          deleted_count,
          deleted_bytes
        )
    end
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

  defp result_log_key({:ok, summary}) do
    if summary.uploaded > 0 or summary.already_present > 0 or
         summary.retained_removed > 0 or summary.spool.deleted_count > 0 do
      {:activity, summary}
    else
      :idle
    end
  end

  defp success_message(summary, spool) do
    "NAS export completed: uploaded=#{summary.uploaded} " <>
      "already_present=#{summary.already_present} " <>
      "retained_removed=#{summary.retained_removed}; " <>
      spool_message(spool)
  end

  defp spool_message(spool) do
    "spool_deleted=#{spool.deleted_count} " <>
      "spool_deleted_bytes=#{spool.deleted_bytes} " <>
      "spool_remaining_bytes=#{spool.remaining_bytes}"
  end
end
