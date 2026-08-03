defmodule Atomcam2NervesApp.WifiProvisioningTest do
  use ExUnit.Case, async: true

  alias Atomcam2NervesApp.WifiProvisioning

  test "no Wi-Fi keys yields no networks" do
    assert WifiProvisioning.networks(%{}) == []
    assert WifiProvisioning.networks(%{"NERVES_WIFI_SSID" => ""}) == []
  end

  test "a single unnumbered pair (backward compatible)" do
    provisioning = %{
      "NERVES_WIFI_SSID" => "home",
      "NERVES_WIFI_PASSPHRASE" => "home-secret"
    }

    assert WifiProvisioning.networks(provisioning) ==
             [%{ssid: "home", psk: "home-secret", key_mgmt: :wpa_psk}]
  end

  test "an open network when the passphrase is empty" do
    assert WifiProvisioning.networks(%{"NERVES_WIFI_SSID" => "guest"}) ==
             [%{ssid: "guest", key_mgmt: :none}]
  end

  test "multiple locations in configured order" do
    provisioning = %{
      "NERVES_WIFI_SSID" => "home",
      "NERVES_WIFI_PASSPHRASE" => "home-secret",
      "NERVES_WIFI_SSID_2" => "office",
      "NERVES_WIFI_PASSPHRASE_2" => "office-secret",
      "NERVES_WIFI_SSID_3" => "site3",
      "NERVES_WIFI_PASSPHRASE_3" => "site3-secret"
    }

    assert WifiProvisioning.networks(provisioning) == [
             %{ssid: "home", psk: "home-secret", key_mgmt: :wpa_psk},
             %{ssid: "office", psk: "office-secret", key_mgmt: :wpa_psk},
             %{ssid: "site3", psk: "site3-secret", key_mgmt: :wpa_psk}
           ]
  end

  test "numbered locations without an unnumbered pair" do
    provisioning = %{
      "NERVES_WIFI_SSID_2" => "office",
      "NERVES_WIFI_PASSPHRASE_2" => "office-secret"
    }

    assert WifiProvisioning.networks(provisioning) ==
             [%{ssid: "office", psk: "office-secret", key_mgmt: :wpa_psk}]
  end

  test "a gap in numbering skips the empty slot" do
    provisioning = %{
      "NERVES_WIFI_SSID" => "home",
      "NERVES_WIFI_PASSPHRASE" => "home-secret",
      "NERVES_WIFI_SSID_3" => "site3",
      "NERVES_WIFI_PASSPHRASE_3" => "site3-secret"
    }

    assert WifiProvisioning.networks(provisioning) == [
             %{ssid: "home", psk: "home-secret", key_mgmt: :wpa_psk},
             %{ssid: "site3", psk: "site3-secret", key_mgmt: :wpa_psk}
           ]
  end

  test "surrounding whitespace is trimmed" do
    provisioning = %{
      "NERVES_WIFI_SSID" => "  home  ",
      "NERVES_WIFI_PASSPHRASE" => "  secret  "
    }

    assert WifiProvisioning.networks(provisioning) ==
             [%{ssid: "home", psk: "secret", key_mgmt: :wpa_psk}]
  end
end
