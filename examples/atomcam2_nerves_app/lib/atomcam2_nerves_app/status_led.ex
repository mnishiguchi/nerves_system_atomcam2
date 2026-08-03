defmodule Atomcam2NervesApp.StatusLed do
  @moduledoc """
  Drive the yellow and blue status LEDs (plain GPIOs, no /sys/class/leds).

  While booting (RTSP not yet publishing) the yellow LED double-blinks
  once a second: 100 ms on, 200 ms off, 100 ms on, 600 ms off. Once the
  native camera reports `:running` (RTSP publishing), the yellow LED goes
  dark and the blue LED stays lit, dipping dark twice every five seconds:
  100 ms off, 200 ms on, 100 ms off, 4600 ms on. If publishing stops,
  the boot pattern comes back.

  busybox `sleep` only does whole seconds, so the sub-second timing lives
  here (`Process.send_after`) instead of in a shell script.
  """

  use GenServer

  require Logger

  # Both status LEDs are wired active-low (drive the pin low to light
  # them). sysfs `active_low` normalizes that, so the patterns below can
  # use 1 = lit.
  @yellow_gpio 38
  @yellow_active_low "1"
  @blue_gpio 39
  @blue_active_low "1"

  @boot_pattern [{1, 100}, {0, 200}, {1, 100}, {0, 600}]
  @publish_pattern [{0, 100}, {1, 200}, {0, 100}, {1, 4600}]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options \\ []) do
    name = Keyword.get(options, :name, __MODULE__)
    GenServer.start_link(__MODULE__, options, name: name)
  end

  @impl GenServer
  def init(_options) do
    setup_gpio(@yellow_gpio, @yellow_active_low)
    setup_gpio(@blue_gpio, @blue_active_low)
    send(self(), :cycle)
    {:ok, %{mode: nil, gpio: nil, steps: []}}
  end

  # A cycle boundary: pick the mode for the next pattern run.
  @impl GenServer
  def handle_info(:cycle, state) do
    mode = current_mode()

    state =
      if mode != state.mode do
        write_value(@yellow_gpio, 0)
        write_value(@blue_gpio, 0)
        %{state | mode: mode}
      else
        state
      end

    {gpio, pattern} =
      case mode do
        :publish -> {@blue_gpio, @publish_pattern}
        :boot -> {@yellow_gpio, @boot_pattern}
      end

    send(self(), :step)
    {:noreply, %{state | gpio: gpio, steps: pattern}}
  end

  def handle_info(:step, %{steps: []} = state) do
    send(self(), :cycle)
    {:noreply, state}
  end

  def handle_info(:step, %{steps: [{value, delay} | rest]} = state) do
    write_value(state.gpio, value)
    Process.send_after(self(), :step, delay)
    {:noreply, %{state | steps: rest}}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  defp current_mode do
    case Atomcam2NervesApp.CameraNative.status() do
      %{phase: :running} -> :publish
      _other -> :boot
    end
  catch
    # CameraNative may not be up (yet); that is by definition still boot.
    _, _ -> :boot
  end

  defp setup_gpio(number, active_low) do
    root = "/sys/class/gpio/gpio#{number}"

    unless File.dir?(root) do
      File.write("/sys/class/gpio/export", Integer.to_string(number))
    end

    File.write(Path.join(root, "direction"), "out")
    File.write(Path.join(root, "active_low"), active_low)
    File.write(Path.join(root, "value"), "0")
  end

  defp write_value(number, value) do
    File.write("/sys/class/gpio/gpio#{number}/value", Integer.to_string(value))
  end
end
