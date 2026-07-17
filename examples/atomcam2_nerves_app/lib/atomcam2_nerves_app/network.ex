defmodule Atomcam2NervesApp.Network do
  @moduledoc """
  Minimal Wi-Fi configuration worker for the AtomCam2 Nerves system.
  """

  use GenServer
  require Logger

  @interface "wlan0"
  @provisioning_path "/media/mmc/nerves-provisioning.conf"
  @wpa_supplicant_path "/media/mmc/wpa_supplicant.conf"
  @retry_interval 1_000
  @max_interface_attempts 30

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl GenServer
  def init(_state) do
    Process.send_after(self(), :configure_wifi, @retry_interval)
    {:ok, %{interface_attempts: 0}}
  end

  @impl GenServer
  def handle_info(:configure_wifi, %{interface_attempts: attempts} = state) do
    cond do
      interface_present?() ->
        configure_wifi_if_needed()
        {:noreply, state}

      attempts + 1 < @max_interface_attempts ->
        Process.send_after(self(), :configure_wifi, @retry_interval)
        {:noreply, %{state | interface_attempts: attempts + 1}}

      true ->
        Logger.error("#{@interface} did not appear after #{@max_interface_attempts} attempts")
        {:noreply, state}
    end
  end

  def status do
    %{
      interface: @interface,
      properties: VintageNet.get_by_prefix(["interface", @interface])
    }
  end

  defp interface_present? do
    File.exists?("/sys/class/net/#{@interface}")
  end

  defp configure_wifi_if_needed do
    case VintageNet.get_configuration(@interface) do
      %{type: VintageNetWiFi} ->
        Logger.info("Keeping existing VintageNet configuration for #{@interface}")

      _other ->
        configure_wifi()
    end
  end

  defp configure_wifi do
    case wifi_config() do
      {:ok, config} ->
        Logger.info("Configuring #{@interface}")

        case VintageNet.configure(@interface, config) do
          :ok ->
            Logger.info("VintageNet accepted the #{@interface} configuration")

          {:error, reason} ->
            Logger.error("VintageNet configuration failed: #{inspect(reason)}")
        end

      :error ->
        Logger.warning("No Wi-Fi credentials found for #{@interface}")
    end
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

      config_from_key_values(%{
        "NERVES_WIFI_SSID" => find_wpa_value(contents, "ssid"),
        "NERVES_WIFI_PASSPHRASE" => find_wpa_value(contents, "psk")
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
      |> Enum.reduce(%{}, fn line, values ->
        case parse_key_value(line) do
          {key, value} -> Map.put(values, key, value)
          :skip -> values
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
        parse_nonempty_key_value(trimmed_line)
    end
  end

  defp parse_nonempty_key_value(line) do
    case String.split(line, "=", parts: 2) do
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
         wps: false,
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
