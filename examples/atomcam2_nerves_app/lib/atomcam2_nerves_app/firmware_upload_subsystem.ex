defmodule Atomcam2NervesApp.FirmwareUploadSubsystem do
  @moduledoc false

  @behaviour :ssh_client_channel

  alias Atomcam2NervesApp.FirmwareUpdate

  require Logger

  @update_command "/usr/bin/atomcam2-firmware-update"
  @upload_directory "/data/atomcam2-firmware-update"

  @impl :ssh_client_channel
  def init(options) do
    Process.flag(:trap_exit, true)

    {:ok,
     %{
       channel_id: nil,
       connection_manager: nil,
       staged_firmware: nil,
       io_device: nil,
       installer_pid: nil,
       update_command:
         Keyword.get(
           options,
           :update_command,
           @update_command
         ),
       phase: :waiting
     }}
  end

  @impl :ssh_client_channel
  def handle_msg(
        {:ssh_channel_up, channel_id, connection_manager},
        state
      ) do
    state = %{
      state
      | channel_id: channel_id,
        connection_manager: connection_manager
    }

    with {:ok, _options} <- FirmwareUpdate.precheck(),
         {:ok, staged_firmware, io_device} <-
           open_staged_firmware() do
      Logger.info("firmware upload started: #{staged_firmware}")

      {:ok,
       %{
         state
         | staged_firmware: staged_firmware,
           io_device: io_device,
           phase: :receiving
       }}
    else
      {:error, reason} ->
        stop_with_error(reason, state)
    end
  end

  def handle_msg(
        {:firmware_install_complete, installer_pid, status, output},
        %{installer_pid: installer_pid} = state
      ) do
    Logger.info("firmware installation completed with status #{status}")

    send_output(state, output)
    finish_channel(state, status)

    if status == 0 do
      spawn(fn ->
        Process.sleep(500)
        Nerves.Runtime.reboot()
      end)
    end

    {:stop, :normal,
     %{
       state
       | installer_pid: nil,
         phase: :finished
     }}
  end

  def handle_msg({:EXIT, installer_pid, reason}, state)
      when installer_pid == state.installer_pid do
    stop_with_error(
      "firmware installer exited: #{inspect(reason)}",
      %{state | installer_pid: nil}
    )
  end

  def handle_msg(message, state) do
    Logger.debug("ignoring firmware upload message: #{inspect(message)}")

    {:ok, state}
  end

  @impl :ssh_client_channel
  def handle_ssh_msg(
        {:ssh_cm, _connection_manager, {:data, _channel_id, 0, data}},
        %{phase: :receiving} = state
      ) do
    case write_chunk(state.io_device, data) do
      :ok ->
        {:ok, state}

      {:error, reason} ->
        stop_with_error(
          "failed to stage firmware: #{format_reason(reason)}",
          state
        )
    end
  end

  def handle_ssh_msg(
        {:ssh_cm, _connection_manager, {:data, _channel_id, 1, _data}},
        state
      ) do
    {:ok, state}
  end

  def handle_ssh_msg(
        {:ssh_cm, _connection_manager, {:eof, _channel_id}},
        %{phase: :receiving} = state
      ) do
    case File.close(state.io_device) do
      :ok ->
        start_installation(%{
          state
          | io_device: nil,
            phase: :installing
        })

      {:error, reason} ->
        stop_with_error(
          "failed to close staged firmware: " <>
            format_reason(reason),
          %{state | io_device: nil}
        )
    end
  end

  def handle_ssh_msg(
        {:ssh_cm, _connection_manager, {:eof, _channel_id}},
        state
      ) do
    {:ok, state}
  end

  def handle_ssh_msg(
        {:ssh_cm, _connection_manager, {:signal, _channel_id, _signal}},
        state
      ) do
    {:ok, state}
  end

  def handle_ssh_msg(
        {:ssh_cm, _connection_manager, {:exit_signal, _channel_id, _signal, _error, _language}},
        state
      ) do
    {:stop, :normal, state}
  end

  def handle_ssh_msg(
        {:ssh_cm, _connection_manager, {:exit_status, _channel_id, _status}},
        state
      ) do
    {:stop, :normal, state}
  end

  def handle_ssh_msg(message, state) do
    Logger.debug(
      "ignoring firmware upload SSH message: " <>
        inspect(message)
    )

    {:ok, state}
  end

  @impl :ssh_client_channel
  def handle_call(_request, _from, state) do
    {:reply, :error, state}
  end

  @impl :ssh_client_channel
  def handle_cast(_message, state) do
    {:noreply, state}
  end

  @impl :ssh_client_channel
  def terminate(_reason, state) do
    close_io_device(state.io_device)
    stop_installer(state.installer_pid)
    remove_staged_firmware(state.staged_firmware)

    :ok
  end

  @impl :ssh_client_channel
  def code_change(_old_version, state, _extra) do
    {:ok, state}
  end

  defp open_staged_firmware do
    case File.mkdir_p(@upload_directory) do
      :ok ->
        open_staged_firmware_file()

      {:error, reason} ->
        {:error,
         "failed to create firmware upload directory: " <>
           format_reason(reason)}
    end
  end

  defp open_staged_firmware_file do
    identifier =
      System.unique_integer([
        :positive,
        :monotonic
      ])

    staged_firmware =
      Path.join(
        @upload_directory,
        "atomcam2-upload-#{identifier}.fw"
      )

    case File.open(
           staged_firmware,
           [:write, :binary, :raw, :exclusive]
         ) do
      {:ok, io_device} ->
        {:ok, staged_firmware, io_device}

      {:error, reason} ->
        {:error,
         "failed to open staged firmware: " <>
           format_reason(reason)}
    end
  end

  defp start_installation(state) do
    parent = self()
    staged_firmware = state.staged_firmware
    update_command = state.update_command

    installer_pid =
      spawn_link(fn ->
        {output, status} =
          run_installation(
            update_command,
            staged_firmware
          )

        send(
          parent,
          {:firmware_install_complete, self(), status, output}
        )
      end)

    {:ok,
     %{
       state
       | installer_pid: installer_pid
     }}
  end

  defp run_installation(
         update_command,
         staged_firmware
       ) do
    System.cmd(
      update_command,
      ["install", staged_firmware],
      stderr_to_stdout: true
    )
  rescue
    exception ->
      {
        Exception.format(
          :error,
          exception,
          __STACKTRACE__
        ),
        1
      }
  catch
    kind, value ->
      {
        "firmware installer failed: " <>
          inspect({kind, value}) <>
          "\n",
        1
      }
  end

  defp write_chunk(io_device, data) do
    try do
      IO.binwrite(io_device, data)
    rescue
      exception ->
        {:error, Exception.message(exception)}
    catch
      kind, value ->
        {:error, inspect({kind, value})}
    end
  end

  defp stop_with_error(reason, state) do
    message = "Error: #{format_reason(reason)}\n"

    send_output(state, message)
    finish_channel(state, 1)

    {:stop, :normal, state}
  end

  defp send_output(_state, ""), do: :ok

  defp send_output(state, output) do
    _ =
      :ssh_connection.send(
        state.connection_manager,
        state.channel_id,
        output
      )

    :ok
  end

  defp finish_channel(state, status) do
    _ =
      :ssh_connection.send_eof(
        state.connection_manager,
        state.channel_id
      )

    _ =
      :ssh_connection.exit_status(
        state.connection_manager,
        state.channel_id,
        status
      )

    _ =
      :ssh_connection.close(
        state.connection_manager,
        state.channel_id
      )

    :ok
  end

  defp close_io_device(nil), do: :ok

  defp close_io_device(io_device) do
    _ = File.close(io_device)
    :ok
  end

  defp stop_installer(nil), do: :ok

  defp stop_installer(installer_pid) do
    if Process.alive?(installer_pid) do
      Process.exit(installer_pid, :kill)
    end

    :ok
  end

  defp remove_staged_firmware(nil), do: :ok

  defp remove_staged_firmware(staged_firmware) do
    _ = File.rm(staged_firmware)
    :ok
  end

  defp format_reason(reason) when is_binary(reason),
    do: reason

  defp format_reason(reason) when is_atom(reason) do
    reason
    |> :file.format_error()
    |> List.to_string()
  end

  defp format_reason(reason), do: inspect(reason)
end
