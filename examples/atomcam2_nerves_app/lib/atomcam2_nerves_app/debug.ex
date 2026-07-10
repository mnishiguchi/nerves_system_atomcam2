defmodule Atomcam2NervesApp.Debug do
  @moduledoc """
  Small IEx helpers for the first ping/SSH milestone.
  """

  def wifi do
    Atomcam2NervesApp.Network.status()
  end

  def ip do
    VintageNet.get(["interface", "wlan0", "addresses"])
  end

  def hostname do
    :inet.gethostname()
  end
end
