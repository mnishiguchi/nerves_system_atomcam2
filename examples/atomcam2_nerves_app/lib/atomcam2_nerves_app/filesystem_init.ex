defmodule Atomcam2NervesApp.FilesystemInit do
  @moduledoc false

  use GenServer

  require Logger

  @runtime Nerves.Runtime
  @runtime_kv Nerves.Runtime.KV
  @mount_info Nerves.Runtime.MountInfo

  @application_partition_prefix "nerves_fw_application_part0"
  @application_partition_uuid "3041e38d-615b-48d4-affb-a7787b5c4c39"
  @initialization_region_size 512 * 256

  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl GenServer
  def init(_args) do
    initialize()
    :ignore
  end

  @doc false
  def classify_initialization_region(region) when is_binary(region) do
    cond do
      byte_size(region) != @initialization_region_size ->
        :unknown

      region == :binary.copy(<<0xFF>>, @initialization_region_size) ->
        :invalidated

      true ->
        :existing
    end
  end

  def classify_initialization_region(_region), do: :unknown

  @doc false
  def classify_initialization_read_result({:ok, region}) do
    {:ok, classify_initialization_region(region)}
  end

  def classify_initialization_read_result({:error, reason}) do
    {:error, reason}
  end

  @doc false
  def initialization_action(:invalidated), do: :format
  def initialization_action(_state), do: :mount_or_repair

  @doc false
  def repair_action(status) when status in [0, 1], do: :retry_mount

  def repair_action(status) when is_integer(status) do
    failure_mask = 4 + 8 + 16 + 32 + 128

    cond do
      Bitwise.band(status, failure_mask) != 0 ->
        :leave_unmounted

      Bitwise.band(status, 2) == 2 ->
        :reboot_required

      true ->
        :leave_unmounted
    end
  end

  def repair_action(_status), do: :leave_unmounted

  defp initialize do
    case application_partition() do
      {:ok, application_partition} ->
        initialize_partition(application_partition)

      {:error, reason} ->
        Logger.error("Application data initialization skipped: #{format_reason(reason)}")

        :unmounted
    end
  end

  defp application_partition do
    prefix = @application_partition_prefix

    application_partition = %{
      devpath: kv_get_active("#{prefix}_devpath"),
      fstype: kv_get_active("#{prefix}_fstype"),
      target: kv_get_active("#{prefix}_target")
    }

    cond do
      application_partition.devpath == nil ->
        {:error, :missing_devpath}

      application_partition.fstype == nil ->
        {:error, :missing_fstype}

      application_partition.target == nil ->
        {:error, :missing_target}

      application_partition.fstype != "ext2" ->
        {:error, {:unsupported_fstype, application_partition.fstype}}

      true ->
        {:ok, application_partition}
    end
  end

  defp initialize_partition(application_partition) do
    case mount_state(application_partition.target) do
      :mounted ->
        Logger.info(
          "Application data partition is mounted read-write; unmounting before filesystem check"
        )

        case unmount(application_partition.target) do
          :ok ->
            initialize_unmounted(application_partition)

          {:error, reason} ->
            log_unmounted_failure("could not unmount read-write filesystem", reason)
        end

      :mounted_read_only ->
        Logger.warning(
          "Application data partition is mounted read-only; unmounting before recovery"
        )

        case unmount(application_partition.target) do
          :ok ->
            initialize_unmounted(application_partition)

          {:error, reason} ->
            log_unmounted_failure("could not unmount read-only filesystem", reason)
        end

      :unmounted ->
        initialize_unmounted(application_partition)

      {:error, reason} ->
        log_unmounted_failure("could not inspect mount state", reason)
    end
  end

  defp initialize_unmounted(application_partition) do
    initialization_state =
      case initialization_state(application_partition.devpath) do
        {:ok, state} ->
          state

        {:error, reason} ->
          {:read_error, reason}
      end

    initialize_from_state(application_partition, initialization_state)
  end

  defp initialize_from_state(application_partition, initialization_state) do
    case initialization_state do
      :invalidated ->
        Logger.info("Application data partition has the explicit initialization marker")

      :unknown ->
        Logger.warning(
          "Application data initialization marker is unknown; automatic formatting is disabled"
        )

      {:read_error, reason} ->
        Logger.warning(
          "Application data initialization marker could not be read; " <>
            "automatic formatting is disabled: #{format_reason(reason)}"
        )

      :existing ->
        :ok
    end

    case initialization_action(initialization_state) do
      :format ->
        format_and_mount(application_partition)

      :mount_or_repair ->
        mount_or_repair(application_partition)
    end
  end

  defp initialization_state(devpath) do
    File.open(devpath, [:read, :binary], fn file ->
      IO.binread(file, @initialization_region_size)
    end)
    |> classify_initialization_read_result()
  end

  defp mount_or_repair(application_partition) do
    case ensure_unmounted(application_partition.target) do
      :ok ->
        Logger.info("Checking application data filesystem before read-write mount")

        {_output, status} =
          runtime_cmd(
            "e2fsck",
            ["-p", application_partition.devpath]
          )

        handle_repair_status(application_partition, status)

      {:error, reason} ->
        log_unmounted_failure("could not ensure filesystem was unmounted", reason)
    end
  end

  defp handle_repair_status(application_partition, status) do
    case repair_action(status) do
      :retry_mount ->
        Logger.info("Application data filesystem check completed with status #{status}")

        case mount(application_partition) do
          :ok ->
            Logger.info("Application data partition mounted after filesystem check")
            :mounted

          {:error, reason} ->
            log_unmounted_failure(
              "mount failed after successful filesystem check",
              reason
            )
        end

      :reboot_required ->
        Logger.error(
          "Application data filesystem check returned status #{status}; " <>
            "leaving /data unmounted because a reboot is required"
        )

        :unmounted

      :leave_unmounted ->
        Logger.error(
          "Application data filesystem check returned status #{status}; " <>
            "leaving /data unmounted without formatting"
        )

        :unmounted
    end
  end

  defp format_and_mount(application_partition) do
    case ensure_unmounted(application_partition.target) do
      :ok ->
        {_output, status} =
          runtime_cmd(
            "mkfs.ext2",
            [
              "-U",
              @application_partition_uuid,
              "-F",
              application_partition.devpath
            ]
          )

        if status == 0 do
          case mount(application_partition) do
            :ok ->
              refresh_shell_history()
              Logger.info("Application data partition formatted and mounted")
              :mounted

            {:error, reason} ->
              log_unmounted_failure("mount failed after formatting", reason)
          end
        else
          Logger.error(
            "Application data formatting failed with status #{status}; " <>
              "leaving /data unmounted"
          )

          :unmounted
        end

      {:error, reason} ->
        log_unmounted_failure("could not ensure filesystem was unmounted", reason)
    end
  end

  defp mount(application_partition) do
    {_output, status} =
      runtime_cmd(
        "mount",
        [
          "-t",
          application_partition.fstype,
          "-o",
          "rw",
          application_partition.devpath,
          application_partition.target
        ]
      )

    case mount_state(application_partition.target) do
      :mounted ->
        :ok

      state ->
        {:error, %{command_status: status, mount_state: state}}
    end
  end

  defp ensure_unmounted(target) do
    case mount_state(target) do
      :unmounted ->
        :ok

      :mounted ->
        unmount(target)

      :mounted_read_only ->
        unmount(target)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp unmount(target) do
    {_output, status} = runtime_cmd("umount", [target])

    case mount_state(target) do
      :unmounted ->
        :ok

      state ->
        {:error, %{command_status: status, mount_state: state}}
    end
  end

  defp mount_state(target) do
    mounts = apply(@mount_info, :get_mounts!, [])
    mount = apply(@mount_info, :find_by_mount_point, [mounts, target])

    cond do
      mount == nil ->
        :unmounted

      apply(@mount_info, :read_only?, [mount]) ->
        :mounted_read_only

      true ->
        :mounted
    end
  rescue
    exception ->
      {:error, Exception.message(exception)}
  end

  defp kv_get_active(key) do
    apply(@runtime_kv, :get_active, [key])
  end

  defp runtime_cmd(command, arguments) do
    apply(@runtime, :cmd, [command, arguments, :return])
  end

  defp log_unmounted_failure(message, reason) do
    Logger.error("Application data initialization failed: #{message}: #{format_reason(reason)}")

    :unmounted
  end

  defp refresh_shell_history do
    Application.put_env(:kernel, :shell_history, shell_history_arg())
  end

  defp shell_history_arg do
    case :init.get_argument(:kernel) do
      {:ok, [arguments]} ->
        find_shell_history_arg(arguments)

      _other ->
        :enabled
    end
  end

  defp find_shell_history_arg([]), do: :enabled

  defp find_shell_history_arg([~c"shell_history", argument | _remaining]) do
    List.to_atom(argument)
  end

  defp find_shell_history_arg([_argument | remaining]) do
    find_shell_history_arg(remaining)
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end
