defmodule Atomcam2NervesApp.WifiProvisioning do
  @moduledoc """
  Build the VintageNet Wi-Fi network list from provisioning key/value pairs.

  Multiple locations are supported by numbering the pairs. The unnumbered pair
  is location 1 for backward compatibility, and `_2`, `_3`, ... add more:

      NERVES_WIFI_SSID=home
      NERVES_WIFI_PASSPHRASE=home-secret
      NERVES_WIFI_SSID_2=office
      NERVES_WIFI_PASSPHRASE_2=office-secret

  VintageNet (wpa_supplicant) then connects to whichever configured network is
  in range, so the same card works across every location without a rebuild —
  edit `nerves-provisioning.conf` on the FAT partition to add one.

  The same `NERVES_WIFI_SSID` / `_2` / ... variables can also be set as
  **build-time environment variables**. Those are captured here at compile
  time and baked into the firmware, so an OTA (`mix upload`) carries the
  Wi-Fi networks without touching the SD card. Nothing is hard-coded — the
  values come from the build host's environment, so no SSID or passphrase
  lives in source. The runtime SD file, when present, overrides per key.
  """

  @build_env_keys ["NERVES_WIFI_SSID", "NERVES_WIFI_PASSPHRASE"] ++
                    Enum.flat_map(2..10, fn n ->
                      ["NERVES_WIFI_SSID_#{n}", "NERVES_WIFI_PASSPHRASE_#{n}"]
                    end)

  # Evaluated at compile time: reads the build host's environment.
  @build_provisioning (for key <- @build_env_keys,
                           value = System.get_env(key),
                           value not in [nil, ""],
                           into: %{},
                           do: {key, value})

  @doc """
  Provisioning captured from build-time environment variables. Merge the
  runtime SD file on top of this (the file wins per key) so an OTA firmware
  carries Wi-Fi networks while the SD can still override per device.
  """
  @spec build_provisioning() :: %{optional(String.t()) => String.t()}
  def build_provisioning, do: @build_provisioning

  @doc """
  Turn a provisioning map (string keys) into a list of VintageNet Wi-Fi
  network maps, in configured order. An entry with an empty SSID is skipped;
  an empty passphrase means an open network.
  """
  @spec networks(%{optional(String.t()) => String.t()}) :: [map()]
  def networks(provisioning) when is_map(provisioning) do
    provisioning
    |> indices()
    |> Enum.flat_map(fn index -> build(provisioning, index) end)
  end

  # Location 1 is the unnumbered pair; further locations are _2, _3, ...
  defp indices(provisioning) do
    numbered =
      provisioning
      |> Map.keys()
      |> Enum.flat_map(fn key ->
        case Regex.run(~r/^NERVES_WIFI_SSID_(\d+)$/, key) do
          [_, n] -> [String.to_integer(n)]
          _ -> []
        end
      end)
      |> Enum.uniq()
      |> Enum.sort()

    [1 | numbered]
  end

  defp build(provisioning, index) do
    {ssid_key, pass_key} =
      if index == 1 do
        {"NERVES_WIFI_SSID", "NERVES_WIFI_PASSPHRASE"}
      else
        {"NERVES_WIFI_SSID_#{index}", "NERVES_WIFI_PASSPHRASE_#{index}"}
      end

    ssid = provisioning |> Map.get(ssid_key, "") |> String.trim()
    passphrase = provisioning |> Map.get(pass_key, "") |> String.trim()

    if ssid == "" do
      []
    else
      [network(ssid, passphrase)]
    end
  end

  defp network(ssid, "") do
    %{ssid: ssid, key_mgmt: :none}
  end

  defp network(ssid, passphrase) do
    %{ssid: ssid, psk: passphrase, key_mgmt: :wpa_psk}
  end
end
