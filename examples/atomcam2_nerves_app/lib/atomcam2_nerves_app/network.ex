defmodule Atomcam2NervesApp.Network do
  @moduledoc """
  Minimal Wi-Fi configuration worker for the first AtomCam2 Nerves milestone.
  """

  use GenServer
  require Logger

  @interface "wlan0"
  @provisioning_path "/media/mmc/nerves-provisioning.conf"
  @wpa_supplicant_path "/media/mmc/wpa_supplicant.conf"

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl GenServer
  def init(state) do
    Process.send_after(self(), :configure_wifi, 2_000)
    {:ok, state}
  end

  @impl GenServer
  def handle_info(:configure_wifi, state) do
    case wifi_config() do
      {:ok, config} ->
        Logger.info("Configuring #{@interface} for AtomCam2 first SSH milestone")
        VintageNet.configure(@interface, config)

      :error ->
        Logger.warning("No Wi-Fi credentials found for #{@interface}")
    end

    {:noreply, state}
  end

  def status do
    %{
      interface: @interface,
      properties: VintageNet.get_by_prefix(["interface", @interface])
    }
  end

  defp wifi_config do
    with :error <- config_from_provisioning(),
         :error <- config_from_env(),
         :error <- config_from_wpa_supplicant() do
      :error
    end
  end

  defp config_from_provisioning do
    @provisioning_path
    |> read_key_values()
    |> config_from_key_values()
  end

  defp config_from_env do
    %{
      "NERVES_WIFI_SSID" => System.get_env("NERVES_WIFI_SSID"),
      "NERVES_WIFI_PASSPHRASE" => System.get_env("NERVES_WIFI_PASSPHRASE")
    }
    |> config_from_key_values()
  end

  defp config_from_wpa_supplicant do
    if File.exists?(@wpa_supplicant_path) do
      contents = File.read!(@wpa_supplicant_path)
      ssid = find_wpa_value(contents, "ssid")
      passphrase = find_wpa_value(contents, "psk")

      config_from_key_values(%{
        "NERVES_WIFI_SSID" => ssid,
        "NERVES_WIFI_PASSPHRASE" => passphrase
      })
    else
      :error
    end
  end

  defp read_key_values(path) do
    if File.exists?(path) do
      path
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.reduce(%{}, fn line, acc ->
        case parse_key_value(line) do
          {key, value} -> Map.put(acc, key, value)
          :skip -> acc
        end
      end)
    else
      %{}
    end
  end

  defp parse_key_value(line) do
    trimmed_line = String.trim(line)

    cond do
      trimmed_line == "" ->
        :skip

      String.starts_with?(trimmed_line, "#") ->
        :skip

      true ->
        case String.split(trimmed_line, "=", parts: 2) do
          [key, value] ->
            key = String.trim(key)

            if key == "" do
              :skip
            else
              {key, String.trim(value)}
            end

          _other ->
            :skip
        end
    end
  end

  defp config_from_key_values(%{"NERVES_WIFI_SSID" => ssid} = values)
       when is_binary(ssid) and ssid != "" do
    passphrase = Map.get(values, "NERVES_WIFI_PASSPHRASE") || ""

    key_mgmt =
      if passphrase == "" do
        :none
      else
        :wpa_psk
      end

    {:ok,
     %{
       type: VintageNetWiFi,
       vintage_net_wifi: %{
         networks: [
           %{
             ssid: ssid,
             psk: passphrase,
             key_mgmt: key_mgmt
           }
         ]
       },
       ipv4: %{method: :dhcp}
     }}
  end

  defp config_from_key_values(_values), do: :error

  defp find_wpa_value(contents, key) do
    pattern = ~r/^\s*#{Regex.escape(key)}="?([^"\n]+)"?/m

    case Regex.run(pattern, contents) do
      [_match, value] -> value
      _other -> nil
    end
  end
end
