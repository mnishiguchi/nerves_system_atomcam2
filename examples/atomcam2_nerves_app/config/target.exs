import Config

config :nerves, :firmware,
  rootfs_overlay: Path.expand("../rootfs_overlay", __DIR__),
  post_processing_script: Path.expand("../scripts/preserve-final-rootfs.sh", __DIR__)

firmware_metadata = %{
  "nerves_fw_active" => "a",
  "a.nerves_fw_product" => Atom.to_string(Mix.Project.config()[:app]),
  "a.nerves_fw_version" => Mix.Project.config()[:version],
  "a.nerves_fw_platform" => "atomcam2",
  "a.nerves_fw_architecture" => "mipsel",
  "a.nerves_fw_application_part0_devpath" => "/dev/rootdisk0p3",
  "a.nerves_fw_application_part0_fstype" => "ext2",
  "a.nerves_fw_application_part0_target" => "/data"
}

config :nerves_runtime,
  kv_backend: {Nerves.Runtime.KVBackend.InMemory, contents: firmware_metadata},
  init_module: Atomcam2NervesApp.FilesystemInit

config :shoehorn,
  init: [:nerves_runtime, :vintage_net, :mdns_lite, :nerves_ssh],
  app: Mix.Project.config()[:app]

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

# Advertise the SSH services provided by NervesSSH.
config :mdns_lite,
  services: [
    %{
      protocol: "ssh",
      transport: "tcp",
      port: 22
    },
    %{
      protocol: "sftp-ssh",
      transport: "tcp",
      port: 22
    }
  ]
