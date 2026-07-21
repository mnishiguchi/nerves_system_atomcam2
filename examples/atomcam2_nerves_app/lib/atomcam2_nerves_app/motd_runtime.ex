defmodule Atomcam2NervesApp.MOTDRuntime do
  @moduledoc false

  @behaviour NervesMOTD.Runtime

  alias NervesMOTD.Runtime.Target

  @impl true
  def applications, do: Target.applications()

  @impl true
  def cpu_temperature, do: Target.cpu_temperature()

  @impl true
  def load_average, do: Target.load_average()

  @impl true
  def memory_stats, do: Target.memory_stats()

  @impl true
  def filesystem_stats(path), do: Target.filesystem_stats(path)

  @impl true
  def time_synchronized?, do: Target.time_synchronized?()

  @impl true
  def active_partition, do: "Prototype p2"

  @impl true
  def firmware_validity, do: :unknown

  @impl true
  def firmware_id, do: "UUID unavailable"
end
