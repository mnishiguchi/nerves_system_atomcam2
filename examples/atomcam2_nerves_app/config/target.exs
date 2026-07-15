import Config

config :nerves, :firmware,
  post_processing_script: Path.expand("../scripts/preserve-final-rootfs.sh", __DIR__)

config :shoehorn,
  init: [:nerves_runtime, :nerves_ssh, :mdns_lite, :vintage_net],
  app: Mix.Project.config()[:app]

public_keys =
  System.user_home!()
  |> Path.join(".ssh/*.pub")
  |> Path.wildcard()
  |> Enum.flat_map(fn path ->
    case File.read(path) do
      {:ok, contents} -> [contents]
      {:error, _reason} -> []
    end
  end)

config :nerves_ssh,
  authorized_keys: public_keys

config :mdns_lite,
  hosts: [:hostname, "nerves"],
  ttl: 120

config :vintage_net,
  regulatory_domain: "00",
  config: []
