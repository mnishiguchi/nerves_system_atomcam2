defmodule Atomcam2NervesApp.Dashboard.Collector do
  @moduledoc """
  Collects the device state as an internal map — nothing else.

  `collect/0` only aggregates the category functions; JSON encoding and
  HTML rendering are separate layers, so adding an output format never
  touches this module. Every category degrades to `"unavailable"` rather
  than failing the whole page, and data comes from OTP APIs and /proc
  first, external commands (df only) last. Status strings are fixed
  enumerations — new values may appear, existing ones never change.
  """

  @call_timeout_ms 200

  @spec collect() :: map()
  def collect do
    %{
      camera: camera(),
      rtsp: rtsp(),
      system: system(),
      memory: memory(),
      network: network(),
      firmware: firmware(),
      storage: storage(),
      logs: logs()
    }
  end

  defp camera do
    case camera_status() do
      %{} = status ->
        %{
          phase: status.phase,
          camd_alive: is_pid(status.camd_pid),
          rtsp_alive: is_pid(status.rtsp_pid),
          camd_version: camd_version(),
          last_error: status.last_error && inspect(status.last_error)
        }

      _other ->
        "unavailable"
    end
  end

  defp camd_version do
    Atomcam2NervesApp.CameraNative.camd_version() || "unavailable"
  rescue
    _exception -> "unavailable"
  end

  defp rtsp do
    %{
      url: rtsp_url(),
      announce_history: history_tail(3)
    }
  end

  defp system do
    %{
      hostname: hostname(),
      uptime_s: uptime_seconds(),
      clock_jst: clock_jst(),
      ntp_synchronized: ntp_synchronized?(),
      loadavg: loadavg()
    }
  end

  defp memory do
    meminfo = read_meminfo()

    beam = :erlang.memory()

    %{
      total_mb: meminfo[:total_mb],
      free_mb: meminfo[:free_mb],
      avail_mb: meminfo[:avail_mb],
      beam_total_mb: div(beam[:total], 1_048_576),
      beam_processes_mb: div(beam[:processes], 1_048_576),
      beam_process_count: :erlang.system_info(:process_count)
    }
  end

  defp network do
    %{
      eth0: ipv4_of("eth0"),
      wlan0: ipv4_of("wlan0")
    }
  end

  defp firmware do
    %{
      version: kv("nerves_fw_version"),
      product: kv("nerves_fw_product"),
      slot: kv_slot(),
      uuid: kv("nerves_fw_uuid")
    }
  end

  defp storage do
    case System.cmd("df", ["-k", "/data"], stderr_to_stdout: true) do
      {output, 0} ->
        case output |> String.split("\n") |> Enum.at(1, "") |> String.split() do
          [_fs, size_kb, used_kb, _avail, percent | _rest] ->
            %{
              data_used_mb: div(String.to_integer(used_kb), 1024),
              data_size_mb: div(String.to_integer(size_kb), 1024),
              data_used_percent: percent
            }

          _other ->
            "unavailable"
        end

      _error ->
        "unavailable"
    end
  rescue
    _exception -> "unavailable"
  end

  defp logs do
    %{tail: log_tail(5)}
  end

  # -- data sources ---------------------------------------------------

  defp camera_status do
    GenServer.call(Atomcam2NervesApp.CameraNative, :status, @call_timeout_ms)
  catch
    _kind, _reason -> "unavailable"
  end

  defp rtsp_url do
    case ipv4_of("eth0") || ipv4_of("wlan0") do
      nil -> "unavailable"
      ip -> "rtsp://#{ip}:8554/video0_unicast"
    end
  end

  defp history_tail(count) do
    case File.read("/media/mmc/boot-announce-history.log") do
      {:ok, contents} ->
        contents |> String.split("\n", trim: true) |> Enum.take(-count)

      {:error, _reason} ->
        []
    end
  end

  defp hostname do
    case :inet.gethostname() do
      {:ok, name} -> List.to_string(name)
      _other -> "unavailable"
    end
  end

  defp uptime_seconds do
    with {:ok, contents} <- File.read("/proc/uptime"),
         {seconds, _rest} <- Float.parse(contents) do
      trunc(seconds)
    else
      _other -> nil
    end
  end

  defp clock_jst do
    DateTime.utc_now()
    |> DateTime.add(9 * 3_600, :second)
    |> Calendar.strftime("%Y-%m-%d %H:%M:%S JST")
  end

  defp ntp_synchronized? do
    NervesTime.synchronized?()
  rescue
    _exception -> "unavailable"
  end

  defp loadavg do
    with {:ok, contents} <- File.read("/proc/loadavg"),
         [one, five, fifteen | _rest] <- String.split(contents) do
      "#{one} #{five} #{fifteen}"
    else
      _other -> "unavailable"
    end
  end

  # Kernel 3.10 has no MemAvailable; approximate it as
  # MemFree + Buffers + Cached.
  defp read_meminfo do
    case File.read("/proc/meminfo") do
      {:ok, contents} ->
        find = fn key ->
          case Regex.run(~r/^#{key}:\s+(\d+)/m, contents) do
            [_line, kb] -> String.to_integer(kb)
            _other -> 0
          end
        end

        free = find.("MemFree")

        %{
          total_mb: div(find.("MemTotal"), 1024),
          free_mb: div(free, 1024),
          avail_mb: div(free + find.("Buffers") + find.("Cached"), 1024)
        }

      {:error, _reason} ->
        %{total_mb: nil, free_mb: nil, avail_mb: nil}
    end
  end

  defp ipv4_of(ifname) do
    with {:ok, interfaces} <- :inet.getifaddrs(),
         {_name, options} <- List.keyfind(interfaces, String.to_charlist(ifname), 0),
         {a, b, c, d} <-
           options
           |> Keyword.get_values(:addr)
           |> Enum.find(&match?({_, _, _, _}, &1)) do
      "#{a}.#{b}.#{c}.#{d}"
    else
      _other -> nil
    end
  end

  defp kv(key) do
    case Nerves.Runtime.KV.get_active(key) do
      value when is_binary(value) and value != "" -> value
      _other -> "unavailable"
    end
  rescue
    _exception -> "unavailable"
  end

  defp kv_slot do
    case Nerves.Runtime.KV.get("nerves_fw_active") do
      slot when is_binary(slot) -> String.upcase(slot)
      _other -> "unavailable"
    end
  rescue
    _exception -> "unavailable"
  end

  # Logs come through the Logger backend; RingLogger today.
  defp log_tail(count) do
    RingLogger.get()
    |> Enum.take(-count)
    |> Enum.map(fn entry -> entry.message |> to_string() |> String.slice(0, 120) end)
  rescue
    _exception -> ["unavailable"]
  catch
    _kind, _reason -> ["unavailable"]
  end
end
