defmodule Atomcam2NervesApp.Debug do
  @moduledoc """
  Small IEx helpers for the first ping/SSH milestone.
  """

  def wifi do
    %{vintage_net_wifi: wifi} =
      config = VintageNet.get_configuration("wlan0")

    %{
      type: config.type,
      ipv4: config.ipv4,
      networks:
        Enum.map(wifi.networks, fn network ->
          Map.take(network, [:ssid, :key_mgmt])
        end),
      wps: wifi.wps,
      addresses:
        VintageNet.get([
          "interface",
          "wlan0",
          "addresses"
        ])
    }
  end

  def ip do
    VintageNet.get(["interface", "wlan0", "addresses"])
  end

  def hostname do
    :inet.gethostname()
  end
end
