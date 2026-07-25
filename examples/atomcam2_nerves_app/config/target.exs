import Config

config :nerves, :firmware,
  rootfs_overlay: Path.expand("../rootfs_overlay", __DIR__),
  post_processing_script: Path.expand("../scripts/preserve-final-rootfs.sh", __DIR__)

firmware_metadata = %{
  "a.nerves_fw_product" => Atom.to_string(Mix.Project.config()[:app]),
  "a.nerves_fw_version" => Mix.Project.config()[:version],
  "a.nerves_fw_platform" => "atomcam2",
  "a.nerves_fw_architecture" => "mipsel",
  "a.nerves_fw_application_part0_devpath" => "/dev/rootdisk0p4",
  "a.nerves_fw_application_part0_fstype" => "ext2",
  "a.nerves_fw_application_part0_target" => "/data",
  "b.nerves_fw_product" => Atom.to_string(Mix.Project.config()[:app]),
  "b.nerves_fw_version" => Mix.Project.config()[:version],
  "b.nerves_fw_platform" => "atomcam2",
  "b.nerves_fw_architecture" => "mipsel",
  "b.nerves_fw_application_part0_devpath" => "/dev/rootdisk0p4",
  "b.nerves_fw_application_part0_fstype" => "ext2",
  "b.nerves_fw_application_part0_target" => "/data"
}

config :nerves_runtime,
  kv_backend: {Atomcam2NervesApp.FirmwareKVBackend, contents: firmware_metadata},
  init_module: Atomcam2NervesApp.FilesystemInit,
  devpath: "/dev/rootdisk0",
  fwup_path: "/usr/libexec/atomcam2/fwup-ops",
  ops_fw_path: "/usr/share/fwup/ops.fw"

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
  authorized_keys: public_keys,
  subsystems: [
    :ssh_sftpd.subsystem_spec(cwd: ~c"/"),
    {~c"fwup", {Atomcam2NervesApp.FirmwareUploadSubsystem, []}}
  ]

config :atomcam2_nerves_app,
  firmware_stabilization_ms: 30_000,
  target: :atomcam2

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
