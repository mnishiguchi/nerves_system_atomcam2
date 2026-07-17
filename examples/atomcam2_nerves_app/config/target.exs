import Config

config :nerves, :firmware,
  rootfs_overlay: Path.expand("../rootfs_overlay", __DIR__),
  post_processing_script: Path.expand("../scripts/preserve-final-rootfs.sh", __DIR__)

config :shoehorn,
  init: [:nerves_runtime, :vintage_net, :mdns_lite, :nerves_ssh],
  app: Mix.Project.config()[:app]

config :nerves_motd,
  logo: "Atom Cam 2 running Nerves\n"

config :logger, backends: [RingLogger]

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

config :ssh_subsystem_fwup,
  precheck_callback: {Atomcam2NervesApp.FirmwareUpdate, :reject_remote_update, []}

config :mdns_lite,
  hosts: [:hostname, "nerves"],
  ttl: 120

config :vintage_net,
  regulatory_domain: "00",
  config: []
