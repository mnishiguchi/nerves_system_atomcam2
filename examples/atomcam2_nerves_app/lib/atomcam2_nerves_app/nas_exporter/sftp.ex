defmodule Atomcam2NervesApp.NasExporter.SFTP do
  @moduledoc false

  require Record

  alias Atomcam2NervesApp.NasExporter.Config

  Record.defrecordp(:file_info, Record.extract(:file_info, from_lib: "kernel/include/file.hrl"))

  @compile {:no_warn_undefined, :ssh}
  @compile {:no_warn_undefined, :ssh_sftp}

  @chunk_size 64 * 1024
  @timeout 15_000
  @hard_call_timeout 16_000
  @cleanup_timeout 2_000

  @type completed_file :: %{
          path: Path.t(),
          relative_path: String.t(),
          size: non_neg_integer()
        }

  @spec export(Config.t(), [completed_file()]) ::
          {:ok, map()} | {:error, term(), map()}
  def export(%Config{} = config, files) do
    case connect(config) do
      {:ok, connection} ->
        try do
          export_connection(connection, config, files)
        after
          close_connection(connection)
        end

      {:error, reason} ->
        {:error, {:connect_failed, reason}, empty_summary()}
    end
  end

  defp export_connection(connection, config, files) do
    case start_channel(connection) do
      {:ok, channel} ->
        try do
          export_channel(channel, config, files)
        after
          stop_channel(channel)
        end

      {:error, reason} ->
        {:error, {:channel_failed, reason}, empty_summary()}
    end
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

  defp stop_channel(channel) do
    case hard_call(
           :stop_channel,
           fn -> apply(:ssh_sftp, :stop_channel, [channel]) end,
           @cleanup_timeout
         ) do
      :ok -> :ok
      _other -> kill_process(channel)
    end
  end

  defp close_connection(connection) do
    case hard_call(
           :close_connection,
           fn -> apply(:ssh, :close, [connection]) end,
           @cleanup_timeout
         ) do
      :ok -> :ok
      _other -> kill_process(connection)
    end
  end

  defp kill_process(pid) when is_pid(pid) do
    if Process.alive?(pid), do: Process.exit(pid, :kill)
    :ok
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
