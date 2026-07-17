defmodule Atomcam2NervesApp.TimeSync do
  @moduledoc false

  use GenServer

  @connection_property ["interface", "wlan0", "connection"]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options) do
    GenServer.start_link(__MODULE__, options, name: __MODULE__)
  end

  @impl GenServer
  def init(_options) do
    :ok = VintageNet.subscribe(@connection_property)

    restart_ntpd_if_online()

    {:ok, nil}
  end

  @impl GenServer
  def handle_info(
        {VintageNet, @connection_property, _old_connection, :internet, _metadata},
        state
      ) do
    restart_ntpd_if_needed()

    {:noreply, state}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  defp restart_ntpd_if_online do
    if VintageNet.get(@connection_property) == :internet do
      restart_ntpd_if_needed()
    end
  end

  defp restart_ntpd_if_needed do
    if NervesTime.synchronized?() do
      :ok
    else
      NervesTime.restart_ntpd()
    end
  end
end
