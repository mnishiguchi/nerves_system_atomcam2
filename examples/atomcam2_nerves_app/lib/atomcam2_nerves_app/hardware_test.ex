defmodule Atomcam2NervesApp.HardwareTest do
  @moduledoc """
  Brief, self-contained hardware checks for the dashboard's 動作確認 tab.

  Each function does a short, visible/audible action and returns quickly;
  the actual work runs in a spawned task so the caller (the HTTP request)
  is not blocked. These touch only peripherals that are safe to poke while
  the camera streams — the status LEDs (via `StatusLed`), the IR LED, and
  the speaker. The IR-cut filter and ISP day/night are intentionally left
  out because driving them fights camd and can stall the RTSP stream.
  """

  require Logger

  alias Atomcam2NervesApp.StatusLed

  @ir_led_gpio 26
  @ir_blinks 5
  @announce_command "/usr/bin/atomcam2-boot-announce"

  @doc "Blink the blue status LED (GPIO 39) a few times."
  def blue_led, do: StatusLed.test(:blue)

  @doc "Blink the yellow status LED (GPIO 38) a few times."
  def yellow_led, do: StatusLed.test(:yellow)

  @doc """
  Blink the IR LED (GPIO 26). Invisible to the eye; check with a phone
  camera or watch the night-vision image brighten.
  """
  def ir_led do
    {:ok, _pid} = Task.start(fn -> blink_ir_led(@ir_blinks) end)
    :ok
  end

  @doc "Play the boot announcement (speaker + amp check)."
  def speaker do
    {:ok, _pid} =
      Task.start(fn -> System.cmd(@announce_command, [], stderr_to_stdout: true) end)

    :ok
  end

  defp blink_ir_led(times) do
    root = "/sys/class/gpio/gpio#{@ir_led_gpio}"

    unless File.dir?(root) do
      File.write("/sys/class/gpio/export", Integer.to_string(@ir_led_gpio))
    end

    File.write(Path.join(root, "direction"), "out")

    Enum.each(1..times, fn _ ->
      File.write(Path.join(root, "value"), "1")
      Process.sleep(250)
      File.write(Path.join(root, "value"), "0")
      Process.sleep(250)
    end)
  end
end
