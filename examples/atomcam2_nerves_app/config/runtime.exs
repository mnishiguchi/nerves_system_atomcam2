import Config

if config_target() != :host do
  # SSH host keys and the time file live on the FAT boot partition, which
  # pre-run mounts before the BEAM starts. Keeping them off /data lets
  # sshd come up with a stable host key and the clock restore early while
  # the (possibly minutes-long) /data filesystem check still runs in the
  # background.
  config :nerves_time,
    time_file: "/media/mmc/.nerves_time",
    await_initialization_timeout: 5_000

  config :nerves_ssh,
    system_dir: "/media/mmc/nerves_ssh",
    user_dir: "/media/mmc/nerves_ssh/default_user"

  provisioning_path = "/media/mmc/nerves-provisioning.conf"

  file_provisioning =
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

  # Networks can be baked in at build time (env vars, carried by OTA) and/or
  # provided by the SD `nerves-provisioning.conf` (per device). The SD file
  # wins per key so a device can be re-pointed without a rebuild.
  provisioning =
    Map.merge(Atomcam2NervesApp.WifiProvisioning.build_provisioning(), file_provisioning)

  # One or more Wi-Fi networks (multiple locations). VintageNet connects to
  # whichever configured network is in range.
  wifi_networks = Atomcam2NervesApp.WifiProvisioning.networks(provisioning)

  # Wired USB Ethernet is always configured. When the adapter is absent,
  # VintageNet keeps eth0 pending without affecting Wi-Fi. When both are
  # connected, VintageNet routes through the wired interface first.
  ethernet_config = [
    {"eth0",
     %{
       type: VintageNetEthernet,
       ipv4: %{method: :dhcp}
     }}
  ]

  wifi_config =
    if wifi_networks == [] do
      []
    else
      [
        {"wlan0",
         %{
           type: VintageNetWiFi,
           vintage_net_wifi: %{
             wps: false,
             networks: wifi_networks
           },
           ipv4: %{method: :dhcp}
         }}
      ]
    end

  config :vintage_net, config: ethernet_config ++ wifi_config

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
