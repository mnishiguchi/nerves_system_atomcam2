defmodule Atomcam2NervesApp.NasExporter.ConfigTest do
  use ExUnit.Case, async: true

  alias Atomcam2NervesApp.NasExporter.Config

  test "loads a strict enabled configuration with boring defaults" do
    assert {:ok, config} =
             Config.parse("""
             # Device-private NAS settings
             enabled=true
             host=nas.local
             user=atomcam2
             user_dir=/data/atomcam2-vendor-camera/nas-ssh
             remote_directory=/volume1/cameras/atomcam2
             """)
             |> then(fn {:ok, values} -> Config.build(values) end)

    assert config.enabled
    assert config.host == "nas.local"
    assert config.port == 22
    assert config.user == "atomcam2"
    assert config.remote_directory == "/volume1/cameras/atomcam2"
    assert config.poll_interval_ms == 60_000
    assert config.retention_days == 20
    assert config.max_spool_bytes == 512 * 1024 * 1024
  end

  test "disabled configuration requires no connection settings" do
    assert {:ok, %{enabled: false}} =
             Config.parse("enabled=false\n")
             |> then(fn {:ok, values} -> Config.build(values) end)
  end

  test "accepts a dedicated SFTP session root" do
    assert {:ok, %{remote_directory: "."}} =
             Config.parse("""
             enabled=true
             host=nas.local
             user=atomcam2
             user_dir=/data/atomcam2-vendor-camera/nas-ssh
             remote_directory=.
             """)
             |> then(fn {:ok, values} -> Config.build(values) end)
  end

  test "rejects polling faster than the one-minute recording cadence" do
    assert {:error, {:invalid_integer, "poll_interval_seconds"}} =
             Config.parse("enabled=false\npoll_interval_seconds=59\n")
             |> then(fn {:ok, values} -> Config.build(values) end)
  end

  test "rejects unknown and duplicate keys" do
    assert {:error, {:unknown_key, 2, "password"}} =
             Config.parse("enabled=true\npassword=secret\n")

    assert {:error, {:duplicate_key, 2, "enabled"}} =
             Config.parse("enabled=true\nenabled=false\n")
  end

  test "rejects unsafe remote roots and relative SSH user directories" do
    base = %{
      "enabled" => "true",
      "host" => "nas.local",
      "user" => "atomcam2",
      "user_dir" => "/data/atomcam2-vendor-camera/nas-ssh"
    }

    assert {:error, {:unsafe_remote_directory, "remote_directory"}} =
             base
             |> Map.put("remote_directory", "/")
             |> Config.build()

    assert {:error, {:unsafe_remote_directory, "remote_directory"}} =
             base
             |> Map.put("remote_directory", "../camera")
             |> Config.build()

    assert {:error, {:unsafe_remote_directory, "remote_directory"}} =
             base
             |> Map.put("remote_directory", "camera/./recordings")
             |> Config.build()

    assert {:error, {:path_must_be_absolute, "user_dir"}} =
             base
             |> Map.put("user_dir", "nas-ssh")
             |> Map.put("remote_directory", "camera")
             |> Config.build()
  end
end
