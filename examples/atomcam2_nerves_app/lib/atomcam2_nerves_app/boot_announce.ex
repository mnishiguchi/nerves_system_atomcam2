defmodule Atomcam2NervesApp.BootAnnounce do
  @moduledoc """
  Play the boot announcement once at application startup.

  The audio work happens in `/usr/bin/atomcam2-boot-announce`: it waits
  for the audio devices (CameraNative loads the modules in the vendor's
  order) and says 「起動しました。」 through the speaker. While the voice
  plays, the infrared LED blinks three times on a one-second cycle —
  timed here because busybox sleep cannot do sub-second delays. This
  only works because operation is native-only; a running `iCamera_app`
  would hold the IMPAudio lock. The status LEDs are driven separately by
  `Atomcam2NervesApp.StatusLed`. The task is fire-and-forget: failures
  are logged and never affect the rest of the supervision tree.
  """

  use Task, restart: :temporary

  require Logger

  @command "/usr/bin/atomcam2-boot-announce"
  @ir_led_gpio 26
  @ir_blinks 3
  # Wait for CameraNative's module loading to surface the audio devices so
  # the IR blink starts together with the voice, not during the wait.
  @audio_wait_ms 25_000

  @spec start_link(keyword()) :: {:ok, pid()}
  def start_link(_options) do
    Task.start_link(&announce/0)
  end

  defp announce do
    wait_for_audio_devices(@audio_wait_ms)

    {:ok, _blink_pid} = Task.start(fn -> blink_ir_led(@ir_blinks) end)

    case System.cmd(@command, [], stderr_to_stdout: true) do
      {_output, 0} ->
        Logger.info("boot announcement played")

      {output, status} ->
        Logger.warning(
          "boot announcement failed (#{status}): #{String.trim(output)}"
        )
    end
  rescue
    exception ->
      Logger.warning("boot announcement error: #{Exception.message(exception)}")
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
