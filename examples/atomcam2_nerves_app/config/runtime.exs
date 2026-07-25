import Config

if config_target() != :host do
  config :nerves_time,
    time_file: "/data/.nerves_time",
    await_initialization_timeout: 5_000

  config :nerves_ssh,
    system_dir: "/data/nerves_ssh",
    user_dir: "/data/nerves_ssh/default_user"

  provisioning_path = "/media/mmc/nerves-provisioning.conf"

  provisioning =
    if File.exists?(provisioning_path) do
      provisioning_path
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.reduce(%{}, fn line, values ->
        case String.split(line, "=", parts: 2) do
          [key, value] -> Map.put(values, String.trim(key), String.trim(value))
          _other -> values
        end
      end)
    else
      %{}
    end

  ssid = Map.get(provisioning, "NERVES_WIFI_SSID")
  passphrase = Map.get(provisioning, "NERVES_WIFI_PASSPHRASE") || ""

  if is_binary(ssid) and ssid != "" do
    key_mgmt =
      if passphrase == "" do
        :none
      else
        :wpa_psk
      end

    config :vintage_net,
      config: [
        {"wlan0",
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
      ]
  end

  sd_keys_path = "/media/mmc/authorized_keys"

  sd_keys =
    if File.exists?(sd_keys_path) do
      sd_keys_path
      |> File.read!()
      |> String.split("\n", trim: true)
    else
      []
    end

  compiled_keys = Application.get_env(:nerves_ssh, :authorized_keys, [])

  config :nerves_ssh,
    authorized_keys: compiled_keys ++ sd_keys

  config :nerves_motd,
    logo: Atomcam2NervesApp.MOTDLogo.render()
end
