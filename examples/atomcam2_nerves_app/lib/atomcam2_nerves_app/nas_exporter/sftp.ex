defmodule Atomcam2NervesApp.NasExporter.SFTP do
  @moduledoc false

  use GenServer

  require Logger
  require Record

  alias Atomcam2NervesApp.NasExporter.Config

  Record.defrecordp(:file_info, Record.extract(:file_info, from_lib: "kernel/include/file.hrl"))

  @compile {:no_warn_undefined, :ssh}
  @compile {:no_warn_undefined, :ssh_sftp}

  @chunk_size 64 * 1024
  @timeout 15_000
  @hard_call_timeout 16_000
  @cleanup_call_timeout @timeout
  @cleanup_exit_timeout 2_000
  @channel_close_timeout 5_000
  @channel_close_poll_interval 50

  @type completed_file :: %{
          path: Path.t(),
          relative_path: String.t(),
          size: non_neg_integer()
        }

  defstruct connection: nil, channel: nil, session_key: nil

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options \\ []) do
    name = Keyword.get(options, :name, __MODULE__)
    GenServer.start_link(__MODULE__, :ok, name: name)
  end

  @spec export(Config.t(), [completed_file()]) ::
          {:ok, map()} | {:error, term(), map()}
  def export(%Config{} = config, files) do
    GenServer.call(__MODULE__, {:export, config, files}, :infinity)
  end

  @spec disconnect() :: :ok
  def disconnect do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      _pid -> GenServer.call(__MODULE__, :disconnect, :infinity)
    end
  end

  @spec status() :: map()
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @impl GenServer
  def init(:ok) do
    {:ok, %__MODULE__{}}
  end

  @impl GenServer
  def handle_call({:export, config, files}, _from, state) do
    case ensure_session(state, config) do
      {:ok, state} ->
        result = export_channel(state.channel, config, files)
        state = if match?({:ok, _summary}, result), do: state, else: close_session(state)
        {:reply, result, state}

      {:error, reason, state} ->
        {:reply, {:error, reason, empty_summary()}, state}
    end
  end

  def handle_call(:disconnect, _from, state) do
    {:reply, :ok, close_session(state)}
  end

  def handle_call(:status, _from, state) do
    status = %{
      connected: resource_alive?(state.connection),
      channel_ready: resource_alive?(state.channel)
    }

    {:reply, status, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    close_session(state)
    :ok
  end

  defp ensure_session(state, config) do
    key = session_key(config)

    if state.session_key == key and resource_alive?(state.connection) and
         resource_alive?(state.channel) do
      {:ok, state}
    else
      state = close_session(state)
      open_session(state, config, key)
    end
  end

  defp open_session(state, config, key) do
    case connect(config) do
      {:ok, connection} ->
        case start_channel(connection) do
          {:ok, channel} ->
            {:ok, %{state | connection: connection, channel: channel, session_key: key}}

          {:error, reason} ->
            close_connection(connection)
            {:error, {:channel_failed, reason}, state}
        end

      {:error, reason} ->
        {:error, {:connect_failed, reason}, state}
    end
  end

  defp close_session(%__MODULE__{} = state) do
    if resource_alive?(state.channel) do
      stop_channel(state.channel, state.connection)
    end

    if resource_alive?(state.connection) do
      close_connection(state.connection)
    end

    %{state | connection: nil, channel: nil, session_key: nil}
  end

  defp resource_alive?(pid) when is_pid(pid), do: Process.alive?(pid)
  defp resource_alive?(_resource), do: false

  defp session_key(config) do
    {
      config.host,
      config.port,
      config.user,
      config.user_dir,
      config.remote_directory
    }
  end

  defp export_channel(channel, config, files) do
    with :ok <-
           ensure_parent_directories(
             channel,
             remote_path(config.remote_directory, ".keep")
           ) do
      result = export_files(channel, config, files)

      case result do
        {:ok, export_summary} ->
          case remove_expired_recordings(channel, config) do
            {:ok, retained_removed} ->
              {:ok, Map.put(export_summary, :retained_removed, retained_removed)}

            {:error, reason} ->
              {:error, {:retention_failed, reason}, export_summary}
          end

        {:error, reason, export_summary} ->
          {:error, reason, export_summary}
      end
    else
      {:error, reason} ->
        {:error, {:remote_root_failed, reason}, empty_summary()}
    end
  end

  @doc false
  @spec expired_date_directory?(String.t(), Date.t(), pos_integer()) :: boolean()
  def expired_date_directory?(date_entry, today, retention_days) do
    case compact_date(date_entry) do
      {:ok, date} -> Date.compare(date, Date.add(today, -retention_days)) == :lt
      {:error, _reason} -> false
    end
  end

  defp connect(config) do
    options = [
      user: String.to_charlist(config.user),
      user_dir: String.to_charlist(config.user_dir),
      user_interaction: false,
      silently_accept_hosts: false,
      connect_timeout: @timeout
    ]

    hard_call(:connect, fn ->
      apply(
        :ssh,
        :connect,
        [String.to_charlist(config.host), config.port, options, @timeout]
      )
    end)
  end

  defp start_channel(connection) do
    hard_call(:start_channel, fn ->
      apply(:ssh_sftp, :start_channel, [connection, [timeout: @timeout]])
    end)
  end

  defp stop_channel(channel, connection) do
    stop_resource(
      channel,
      :stop_channel,
      fn -> apply(:ssh_sftp, :stop_channel, [channel]) end
    )

    await_channel_close(connection)
  end

  defp close_connection(connection) do
    stop_resource(
      connection,
      :close_connection,
      fn -> apply(:ssh, :close, [connection]) end
    )
  end

  defp stop_resource(pid, operation, stop) when is_pid(pid) do
    monitor_ref = Process.monitor(pid)
    result = hard_call(operation, stop, @cleanup_call_timeout)

    case await_resource_exit(pid, monitor_ref, @cleanup_exit_timeout) do
      :ok ->
        log_cleanup_error(operation, result)

      :timeout ->
        Logger.warning("NAS SFTP #{operation} did not terminate its resource; forcing shutdown")

        Process.exit(pid, :kill)
        await_forced_resource_exit(pid, monitor_ref, operation)
    end

    Process.demonitor(monitor_ref, [:flush])
    :ok
  end

  defp await_resource_exit(pid, monitor_ref, timeout) do
    receive do
      {:DOWN, ^monitor_ref, :process, ^pid, _reason} -> :ok
    after
      timeout -> :timeout
    end
  end

  defp await_forced_resource_exit(pid, monitor_ref, operation) do
    case await_resource_exit(pid, monitor_ref, @cleanup_exit_timeout) do
      :ok ->
        :ok

      :timeout ->
        Logger.error("NAS SFTP #{operation} resource remained alive after forced shutdown")
    end
  end

  defp log_cleanup_error(_operation, :ok), do: :ok

  defp log_cleanup_error(operation, result) do
    Logger.warning("NAS SFTP #{operation} returned #{inspect(result)}")
  end

  defp await_channel_close(connection) do
    deadline = System.monotonic_time(:millisecond) + @channel_close_timeout
    await_channel_close(connection, deadline)
  end

  defp await_channel_close(connection, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 1)

    case hard_call(
           :channel_close,
           fn -> apply(:ssh, :connection_info, [connection, :channels]) end,
           remaining
         ) do
      {:channels, []} ->
        :ok

      {:channels, _channels} ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(@channel_close_poll_interval)
          await_channel_close(connection, deadline)
        else
          Logger.warning("NAS SFTP channel close was not acknowledged before disconnect")
        end

      {:error, reason} ->
        Logger.warning("NAS SFTP channel close check returned #{inspect(reason)}")
    end
  end

  defp export_files(channel, config, files) do
    Enum.reduce_while(files, {:ok, empty_summary()}, fn file, {:ok, summary} ->
      case export_file(channel, config, file) do
        {:ok, disposition} ->
          {:cont, {:ok, increment(summary, disposition, file)}}

        {:error, reason} ->
          {:halt, {:error, {:upload_failed, file.relative_path, reason}, summary}}
      end
    end)
  end

  defp export_file(channel, config, file) do
    final_path = remote_path(config.remote_directory, file.relative_path)
    temporary_path = final_path <> ".uploading"

    with :ok <- ensure_parent_directories(channel, final_path) do
      case remote_size(channel, final_path) do
        {:ok, size} when size == file.size ->
          {:ok, :already_present}

        {:ok, size} ->
          {:error, {:remote_file_conflict, size, file.size}}

        :missing ->
          upload_file(channel, file.path, temporary_path, final_path, file.size)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp upload_file(channel, local_path, temporary_path, final_path, expected_size) do
    _result = sftp(:delete, [channel, String.to_charlist(temporary_path)])

    with {:ok, handle} <-
           sftp(:open, [
             channel,
             String.to_charlist(temporary_path),
             [:write, :binary]
           ]),
         :ok <- copy_and_close(channel, handle, local_path),
         {:ok, ^expected_size} <- remote_size(channel, temporary_path),
         :ok <-
           sftp(:rename, [
             channel,
             String.to_charlist(temporary_path),
             String.to_charlist(final_path)
           ]) do
      {:ok, :uploaded}
    else
      {:ok, actual_size} -> {:error, {:temporary_size_mismatch, actual_size, expected_size}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp copy_and_close(channel, handle, local_path) do
    copy_result = copy_local_file(channel, handle, local_path)
    close_result = sftp(:close, [channel, handle])

    case {copy_result, close_result} do
      {:ok, :ok} -> :ok
      {{:error, reason}, _close_result} -> {:error, reason}
      {:ok, {:error, reason}} -> {:error, {:remote_close_failed, reason}}
    end
  end

  defp copy_local_file(channel, handle, local_path) do
    case File.open(local_path, [:read, :binary]) do
      {:ok, file} ->
        try do
          copy_chunks(channel, handle, file)
        after
          File.close(file)
        end

      {:error, reason} ->
        {:error, {:local_open_failed, reason}}
    end
  end

  defp copy_chunks(channel, handle, file) do
    case IO.binread(file, @chunk_size) do
      :eof ->
        :ok

      {:error, reason} ->
        {:error, {:local_read_failed, reason}}

      data when is_binary(data) ->
        case sftp(:write, [channel, handle, data]) do
          :ok -> copy_chunks(channel, handle, file)
          {:error, reason} -> {:error, {:remote_write_failed, reason}}
        end
    end
  end

  defp ensure_parent_directories(channel, path) do
    path
    |> remote_parent()
    |> remote_directory_chain()
    |> Enum.reduce_while(:ok, fn directory, :ok ->
      case ensure_directory(channel, directory) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp ensure_directory(channel, directory) do
    case sftp(:read_file_info, [channel, String.to_charlist(directory)]) do
      {:ok, info} ->
        if file_info(info, :type) == :directory do
          :ok
        else
          {:error, {:remote_path_is_not_directory, directory}}
        end

      {:error, reason} when reason in [:enoent, :no_such_file] ->
        sftp(:make_dir, [channel, String.to_charlist(directory)])

      {:error, reason} ->
        {:error, {:remote_directory_check_failed, directory, reason}}
    end
  end

  defp remote_size(channel, path) do
    case sftp(:read_file_info, [channel, String.to_charlist(path)]) do
      {:ok, info} -> {:ok, file_info(info, :size)}
      {:error, reason} when reason in [:enoent, :no_such_file] -> :missing
      {:error, reason} -> {:error, {:remote_stat_failed, reason}}
    end
  end

  defp remove_expired_recordings(channel, config) do
    with {:ok, date_entries} <- list_directory(channel, config.remote_directory) do
      date_entries
      |> Enum.filter(&String.match?(&1, ~r/\A\d{8}\z/))
      |> Enum.reduce_while({:ok, 0}, fn date_entry, {:ok, deleted} ->
        if expired_date_directory?(date_entry, Date.utc_today(), config.retention_days) do
          case remove_date_recordings(channel, config.remote_directory, date_entry) do
            {:ok, removed} -> {:cont, {:ok, deleted + removed}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        else
          {:cont, {:ok, deleted}}
        end
      end)
    end
  end

  defp compact_date(<<year::binary-size(4), month::binary-size(2), day::binary-size(2)>>) do
    with {year, ""} <- Integer.parse(year),
         {month, ""} <- Integer.parse(month),
         {day, ""} <- Integer.parse(day) do
      Date.new(year, month, day)
    else
      _other -> {:error, :invalid_date}
    end
  end

  defp compact_date(_date_entry), do: {:error, :invalid_date}

  defp remove_date_recordings(channel, root, date_entry) do
    date_directory = remote_path(root, date_entry)

    with {:ok, hour_entries} <- list_directory(channel, date_directory) do
      hour_entries
      |> Enum.filter(&String.match?(&1, ~r/\A\d{2}\z/))
      |> Enum.reduce_while({:ok, 0}, fn hour_entry, {:ok, deleted} ->
        hour_directory = remote_path(date_directory, hour_entry)

        case remove_hour_recordings(channel, hour_directory) do
          {:ok, removed} -> {:cont, {:ok, deleted + removed}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  defp remove_hour_recordings(channel, hour_directory) do
    with {:ok, entries} <- list_directory(channel, hour_directory) do
      entries
      |> Enum.filter(&String.match?(&1, ~r/\A\d{2}\.mp4(?:\.uploading)?\z/))
      |> Enum.reduce_while({:ok, 0}, fn entry, {:ok, deleted} ->
        path = remote_path(hour_directory, entry)

        case sftp(:delete, [channel, String.to_charlist(path)]) do
          :ok -> {:cont, {:ok, deleted + 1}}
          {:error, reason} -> {:halt, {:error, {:remote_delete_failed, path, reason}}}
        end
      end)
    end
  end

  defp list_directory(channel, path) do
    case sftp(:list_dir, [channel, String.to_charlist(path)]) do
      {:ok, entries} -> {:ok, Enum.map(entries, &List.to_string/1)}
      {:error, reason} -> {:error, {:remote_list_failed, path, reason}}
    end
  end

  defp remote_directory_chain(path) do
    absolute? = String.starts_with?(path, "/")

    {_current, directories} =
      path
      |> String.split("/", trim: true)
      |> Enum.reduce({"", []}, fn component, {current, directories} ->
        next =
          cond do
            current == "" and absolute? -> "/" <> component
            current == "" -> component
            true -> current <> "/" <> component
          end

        {next, directories ++ [next]}
      end)

    directories
  end

  defp remote_parent(path) do
    parent =
      path
      |> String.split("/")
      |> Enum.drop(-1)
      |> Enum.join("/")

    if parent == "" and String.starts_with?(path, "/"), do: "/", else: parent
  end

  defp remote_path(parent, child) do
    String.trim_trailing(parent, "/") <> "/" <> String.trim_leading(child, "/")
  end

  defp sftp(function, arguments) do
    hard_call(function, fn ->
      apply(:ssh_sftp, function, arguments ++ [@timeout])
    end)
  end

  defp hard_call(operation, function, timeout \\ @hard_call_timeout) do
    caller = self()
    result_ref = make_ref()

    {pid, monitor_ref} =
      spawn_monitor(fn ->
        result =
          try do
            function.()
          rescue
            exception ->
              {:error,
               {:exception, operation, exception.__struct__, Exception.message(exception)}}
          catch
            kind, reason -> {:error, {kind, operation, reason}}
          end

        send(caller, {result_ref, result})
      end)

    receive do
      {^result_ref, result} ->
        Process.demonitor(monitor_ref, [:flush])
        result

      {:DOWN, ^monitor_ref, :process, ^pid, reason} ->
        {:error, {:process_exit, operation, reason}}
    after
      timeout ->
        Process.exit(pid, :kill)
        await_call_exit(pid, monitor_ref)
        flush_call_result(result_ref)
        {:error, {:timeout, operation}}
    end
  end

  defp await_call_exit(pid, monitor_ref) do
    receive do
      {:DOWN, ^monitor_ref, :process, ^pid, _reason} -> :ok
    after
      1_000 ->
        Process.demonitor(monitor_ref, [:flush])
        :ok
    end
  end

  defp flush_call_result(result_ref) do
    receive do
      {^result_ref, _result} -> :ok
    after
      0 -> :ok
    end
  end

  defp empty_summary do
    %{uploaded: 0, already_present: 0, retained_removed: 0, completed_files: []}
  end

  defp increment(summary, key, file) do
    summary
    |> Map.update!(key, &(&1 + 1))
    |> Map.update!(:completed_files, &[file | &1])
  end
end
