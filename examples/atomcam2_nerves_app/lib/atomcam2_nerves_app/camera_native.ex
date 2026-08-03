defmodule Atomcam2NervesApp.CameraNative do
  @moduledoc """
  Boot integration for the native camera stack (Stage 5, first slice).

  Drives the iCamera_app-free pipeline: loads the camera kernel modules,
  then supervises `atomcam2-camd` (libimp capture + H.264 encode into
  v4l2loopback) and `v4l2rtspserver` as OS processes via
  `MuonTrap.Daemon`, restarting them if they exit. Everything needed
  lives in the rootfs, /atom, and /tmp, so the camera comes up even while
  a long /data filesystem check is still running.

  Auto-start is opt-out: `/data/atomcam2-native-camera/auto-start.conf`
  with `enabled=false` disables it; a missing (or not yet mounted) file
  means enabled, because native is the only camera mode in this
  deployment.
  """

  use GenServer

  require Logger

  @config_path "/data/atomcam2-native-camera/auto-start.conf"
  @camd_path "/usr/bin/atomcam2-camd"
  @loopback_device "/dev/video0"
  @libimp_path "/atom/system/lib/libimp.so"
  @driver_root "/atom/system/driver"
  @ld_library_path "/atom/system/lib:/atom/lib"

  # Effectively "run forever": camd exits after this many frames and the
  # daemon supervisor starts it again.
  @camd_frames "2000000000"
  @camd_args [@camd_frames, @loopback_device, "gc2053", "0x37"]
  @camd_ctl_path "/tmp/camd.ctl"
  @rtsp_args ["-Q", "2", "-P", "8554", @loopback_device]

  # The loopback writer has to set the H.264 format (S_FMT) before
  # v4l2rtspserver opens the device, so give camd a head start.
  @rtsp_delay_ms 8_000
  @poll_interval_ms 5_000
  # The top-left OSD line on the video: IP, firmware version, available
  # memory, CPU usage. Refreshed every few seconds ("realtime").
  @info_refresh_ms 3_000

  # The vendor start sequence loads tx_isp first and audio right after;
  # loading audio.ko before tx_isp leaves the codec half-initialized
  # (IMP_AO_Enable returns -1 and /dev/dsp never appears), so all camera
  # and audio modules are loaded here, in this exact order. The boot
  # announcement waits for the audio devices instead of loading modules.
  @camera_modules [
    {"tx_isp_t31", "tx-isp-t31.ko", ["isp_clk=100000000"]},
    {"audio", "audio.ko", ["spk_gpio=-1"]},
    {"avpu", "avpu.ko", []},
    {"sinfo", "sinfo.ko", []},
    {"sensor_gc2053_t31", "sensor_gc2053_t31.ko", ["data_interface=1"]},
    {"speaker_ctl", "speaker_ctl.ko", []}
  ]

  defstruct phase: :not_checked,
            camd_pid: nil,
            rtsp_pid: nil,
            last_error: nil,
            cpu_sample: nil

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options \\ []) do
    name = Keyword.get(options, :name, __MODULE__)
    GenServer.start_link(__MODULE__, options, name: name)
  end

  @spec status(GenServer.server()) :: map()
  def status(server \\ __MODULE__) do
    GenServer.call(server, :status)
  end

  @impl GenServer
  def init(_options) do
    # The daemons are linked; trap exits so a crashing camd or RTSP server
    # is restarted here with backoff instead of taking this server down.
    Process.flag(:trap_exit, true)
    # Single self-rescheduling timer (started once here so camd restarts
    # cannot stack additional timers).
    Process.send_after(self(), :update_info, 15_000)
    {:ok, %__MODULE__{}, {:continue, :check}}
  end

  @impl GenServer
  def handle_continue(:check, state) do
    {:noreply, check(state)}
  end

  @impl GenServer
  def handle_info(:check, state) do
    {:noreply, check(state)}
  end

  def handle_info(:start_rtsp, state) do
    {:noreply, start_rtsp(state)}
  end

  def handle_info(:update_info, state) do
    {cpu_percent, cpu_sample} = cpu_usage(state.cpu_sample)

    if alive?(state.camd_pid) do
      write_ctl("info " <> system_info_line(cpu_percent))
    end

    Process.send_after(self(), :update_info, @info_refresh_ms)
    {:noreply, %{state | cpu_sample: cpu_sample}}
  end

  def handle_info({:EXIT, pid, reason}, %{camd_pid: pid} = state) do
    Logger.warning("camd exited (#{inspect(reason)}); restarting")
    schedule_check()
    {:noreply, %{state | camd_pid: nil, phase: :waiting}}
  end

  def handle_info({:EXIT, pid, reason}, %{rtsp_pid: pid} = state) do
    Logger.warning("v4l2rtspserver exited (#{inspect(reason)}); restarting")
    Process.send_after(self(), :start_rtsp, @poll_interval_ms)
    {:noreply, %{state | rtsp_pid: nil, phase: :degraded}}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_call(:status, _from, state) do
    {:reply, Map.from_struct(state), state}
  end

  defp check(state) do
    cond do
      not enabled?() ->
        log_once(state, :disabled, "Native camera auto-start is disabled")
        schedule_check()
        %{state | phase: :disabled}

      not ready?() ->
        log_once(state, :waiting, "Native camera is waiting for #{inspect(missing())}")
        schedule_check()
        %{state | phase: :waiting}

      alive?(state.camd_pid) ->
        state

      true ->
        start_stack(state)
    end
  end

  defp start_stack(state) do
    with :ok <- load_camera_modules(),
         :ok <- ensure_dsp_node(),
         {:ok, camd_pid} <- start_camd() do
      Process.send_after(self(), :start_rtsp, @rtsp_delay_ms)
      Logger.info("Native camera started (camd)")
      %{state | phase: :starting, camd_pid: camd_pid, last_error: nil}
    else
      {:error, reason} ->
        Logger.warning("Native camera start failed: #{inspect(reason)}")
        schedule_check()
        %{state | phase: :waiting, last_error: reason}
    end
  end

  defp start_rtsp(%{rtsp_pid: rtsp_pid} = state) when is_pid(rtsp_pid) do
    if alive?(rtsp_pid), do: state, else: start_rtsp(%{state | rtsp_pid: nil})
  end

  defp start_rtsp(state) do
    case MuonTrap.Daemon.start_link(
           "/usr/bin/v4l2rtspserver",
           @rtsp_args,
           log_output: :info,
           log_prefix: "v4l2rtspserver: ",
           stderr_to_stdout: true
         ) do
      {:ok, pid} ->
        Logger.info("Native camera RTSP server started on port 8554")
        %{state | phase: :running, rtsp_pid: pid}

      {:error, reason} ->
        Logger.warning("v4l2rtspserver start failed: #{inspect(reason)}")
        %{state | phase: :degraded, last_error: reason}
    end
  end

  defp start_camd do
    MuonTrap.Daemon.start_link(
      @camd_path,
      @camd_args,
      env: [{"LD_LIBRARY_PATH", @ld_library_path}],
      log_output: :debug,
      log_prefix: "camd: ",
      stderr_to_stdout: true
    )
  end

  defp enabled? do
    case File.read(@config_path) do
      {:ok, contents} -> String.trim(contents) != "enabled=false"
      {:error, _reason} -> true
    end
  end

  defp ready?, do: missing() == []

  defp missing do
    checks = [
      {@loopback_device, &loopback_present?/0},
      {@libimp_path, fn -> File.exists?(@libimp_path) end}
    ]

    for {name, present?} <- checks, not present?.(), do: name
  end

  defp loopback_present? do
    match?({:ok, %File.Stat{type: :device}}, File.stat(@loopback_device))
  end

  defp load_camera_modules do
    Enum.reduce_while(@camera_modules, :ok, fn {name, file, args}, :ok ->
      if module_loaded?(name) do
        {:cont, :ok}
      else
        case System.cmd(
               "/sbin/insmod",
               [Path.join(@driver_root, file) | args],
               stderr_to_stdout: true
             ) do
          {_output, 0} ->
            Logger.info("Loaded camera module #{name}")
            {:cont, :ok}

          {output, status} ->
            {:halt, {:error, {:insmod, name, status, String.trim(output)}}}
        end
      end
    end)
  end

  # devtmpfs has been seen skipping the OSS node even after a successful
  # codec probe; the driver registers char major 14 ("sound"), so create
  # the classic /dev/dsp (14, 3) ourselves when it is missing.
  defp ensure_dsp_node do
    if File.exists?("/dev/dsp") do
      :ok
    else
      case System.cmd("/bin/mknod", ["/dev/dsp", "c", "14", "3"], stderr_to_stdout: true) do
        {_output, 0} ->
          Logger.info("Created /dev/dsp device node")
          :ok

        {output, status} ->
          Logger.warning("mknod /dev/dsp failed (#{status}): #{String.trim(output)}")
          :ok
      end
    end
  end

  defp module_loaded?(name) do
    case File.read("/proc/modules") do
      {:ok, contents} ->
        contents
        |> String.split("\n")
        |> Enum.any?(&String.starts_with?(&1, name <> " "))

      {:error, _reason} ->
        false
    end
  end

  defp schedule_check do
    Process.send_after(self(), :check, @poll_interval_ms)
  end

  defp alive?(pid), do: is_pid(pid) and Process.alive?(pid)

  # camd consumes one command per write; the info line simply overwrites
  # whatever was pending, which is fine for a periodic status refresh.
  defp write_ctl(command) do
    File.write(@camd_ctl_path, command <> "\n")
  end

  # "192.168.1.77 v0.4.0 M:21M C:37%" — ASCII only, 40 columns max (the
  # OSD font covers printable ASCII).
  defp system_info_line(cpu_percent) do
    [first_ipv4(), firmware_version(), mem_available(), cpu_text(cpu_percent)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
    |> String.replace(~r/[^ -~]/, "?")
    |> String.slice(0, 40)
  end

  # Kernel 3.10 has no MemAvailable; approximate it as
  # MemFree + Buffers + Cached (page cache is reclaimable).
  defp mem_available do
    with {:ok, contents} <- File.read("/proc/meminfo") do
      kb =
        ~r/^(?:MemFree|Buffers|Cached):\s+(\d+)/m
        |> Regex.scan(contents, capture: :all_but_first)
        |> List.flatten()
        |> Enum.map(&String.to_integer/1)
        |> Enum.sum()

      if kb > 0, do: "M:#{div(kb, 1024)}M"
    else
      _other -> nil
    end
  end

  defp cpu_text(nil), do: nil
  defp cpu_text(percent), do: "C:#{percent}%"

  # Overall CPU usage from consecutive /proc/stat samples: busy delta over
  # total delta. The first call only primes the sample.
  defp cpu_usage(previous_sample) do
    with {:ok, contents} <- File.read("/proc/stat"),
         ["cpu" | fields] <- contents |> String.split("\n", parts: 2) |> hd() |> String.split() do
      counters = Enum.map(fields, &String.to_integer/1)
      total = Enum.sum(counters)
      idle = Enum.at(counters, 3, 0) + Enum.at(counters, 4, 0)
      busy = total - idle

      case previous_sample do
        {previous_busy, previous_total} when total > previous_total ->
          percent = round((busy - previous_busy) * 100 / (total - previous_total))
          {min(percent, 100), {busy, total}}

        _other ->
          {nil, {busy, total}}
      end
    else
      _other -> {nil, previous_sample}
    end
  end

  defp first_ipv4 do
    with {:ok, interfaces} <- :inet.getifaddrs() do
      # Wired first, then Wi-Fi, so the address people can reach wins.
      Enum.find_value(["eth0", "wlan0"], fn ifname ->
        interfaces
        |> List.keyfind(String.to_charlist(ifname), 0)
        |> case do
          {_name, options} ->
            options
            |> Keyword.get_values(:addr)
            |> Enum.find(&match?({_, _, _, _}, &1))
            |> case do
              {a, b, c, d} -> "#{a}.#{b}.#{c}.#{d}"
              _other -> nil
            end

          nil ->
            nil
        end
      end)
    else
      _error -> nil
    end
  end

  defp firmware_version do
    case Nerves.Runtime.KV.get_active("nerves_fw_version") do
      version when is_binary(version) and version != "" -> "v" <> version
      _other -> nil
    end
  rescue
    _exception -> nil
  end

  # Waiting is polled every few seconds; only log when the phase changes.
  defp log_once(%{phase: phase}, phase, _message), do: :ok
  defp log_once(_state, _phase, message), do: Logger.info(message)
end
