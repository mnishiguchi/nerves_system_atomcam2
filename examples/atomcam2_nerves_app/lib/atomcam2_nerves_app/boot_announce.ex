defmodule Atomcam2NervesApp.BootAnnounce do
  @moduledoc """
  Play the boot announcement once at application startup: three short
  beeps followed by 「起動しました。」 (one PCM file), with the infrared
  LED blinking three times on a one-second cycle in sync.

  Cold boots intermittently leave the audio driver broken
  (`IMP_AO_Enable = -1`, no /dev/dsp) even with the correct module load
  order, so playback retries every 30 seconds. Every attempt logs the
  player's step output, and the final outcome is appended to
  `/data/boot-announce-history.log` (once /data is mounted) so the
  failure pattern can be tracked across boots: if a retry eventually
  succeeds the hardware just needed time, if all attempts fail the boot
  is permanently wedged and the module-load timing is to blame.
  """

  use Task, restart: :temporary

  require Logger

  @command "/usr/bin/atomcam2-boot-announce"
  @history_path "/data/boot-announce-history.log"
  @ir_led_gpio 26
  @ir_blinks 3
  @max_attempts 6
  @retry_delay_ms 30_000
  # Wait for CameraNative's module loading to surface the audio devices so
  # the IR blink starts together with the sound, not during the wait.
  @audio_wait_ms 25_000

  @spec start_link(keyword()) :: {:ok, pid()}
  def start_link(_options) do
    Task.start_link(&announce/0)
  end

  defp announce do
    attempt(1)
  rescue
    exception ->
      Logger.warning("boot announcement error: #{Exception.message(exception)}")
  end

  defp attempt(number) when number > @max_attempts do
    Logger.warning(
      "boot announcement gave up after #{@max_attempts} attempts (audio wedged this boot)"
    )

    record_history("failed after #{@max_attempts} attempts")
  end

  defp attempt(number) do
    if number == 1, do: wait_for_audio_devices(@audio_wait_ms)

    {:ok, _blink_pid} = Task.start(fn -> blink_ir_led(@ir_blinks) end)

    case System.cmd(@command, [], stderr_to_stdout: true) do
      {output, 0} ->
        Logger.info("boot announcement played (attempt #{number})")
        if number > 1, do: Logger.info("announcement recovery detail: #{String.trim(output)}")
        record_history("ok on attempt #{number}")

      {output, status} ->
        Logger.warning(
          "boot announcement attempt #{number} failed (#{status}): #{String.trim(output)}"
        )

        Process.sleep(@retry_delay_ms)
        attempt(number + 1)
    end
  end

  defp wait_for_audio_devices(remaining_ms) when remaining_ms <= 0, do: :timeout

  defp wait_for_audio_devices(remaining_ms) do
    if File.exists?("/dev/dsp") and File.exists?("/dev/speakerctl") do
      :ok
    else
      Process.sleep(200)
      wait_for_audio_devices(remaining_ms - 200)
    end
  end

  # One line per boot, e.g. "2026-08-04 02:10:33Z up=41s ok on attempt 1".
  # /data may still be under its filesystem check; retry for a few minutes.
  defp record_history(result) do
    line =
      "#{DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_string()} " <>
        "up=#{uptime_seconds()}s #{result}\n"

    append_when_writable(line, 30)
  end

  defp append_when_writable(_line, 0), do: :ok

  defp append_when_writable(line, tries_left) do
    case File.write(@history_path, line, [:append]) do
      :ok ->
        :ok

      {:error, _reason} ->
        Process.sleep(10_000)
        append_when_writable(line, tries_left - 1)
    end
  end

  defp uptime_seconds do
    with {:ok, contents} <- File.read("/proc/uptime"),
         {seconds, _rest} <- Float.parse(contents) do
      trunc(seconds)
    else
      _other -> -1
    end
  end

  # One-second cycle: 500 ms on, 500 ms off. The IR light is invisible to
  # the naked eye but shows purple on a phone camera and lights up the
  # scene on the night-vision video.
  defp blink_ir_led(times) do
    gpio_root = "/sys/class/gpio/gpio#{@ir_led_gpio}"

    unless File.dir?(gpio_root) do
      File.write("/sys/class/gpio/export", Integer.to_string(@ir_led_gpio))
    end

    File.write(Path.join(gpio_root, "direction"), "out")
    File.write(Path.join(gpio_root, "active_low"), "0")

    for _blink <- 1..times do
      File.write(Path.join(gpio_root, "value"), "1")
      Process.sleep(500)
      File.write(Path.join(gpio_root, "value"), "0")
      Process.sleep(500)
    end

    :ok
  end
end
