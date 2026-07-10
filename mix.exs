defmodule NervesSystemAtomcam2.MixProject do
  use Mix.Project

  @app :nerves_system_atomcam2
  @source_url "https://github.com/mnishiguchi/nerves_system_atomcam2"
  @version Path.join(__DIR__, "VERSION")
           |> File.read!()
           |> String.trim()

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.16",
      archives: [nerves_bootstrap: "~> 1.15"],
      compilers: Mix.compilers() ++ [:nerves_package],
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      description: "Experimental minimal Nerves system for AtomCam2",
      package: package(),
      nerves_package: nerves_package(),
      deps: deps(),
      aliases: [
        loadconfig: [&bootstrap/1],
        smoke: ["cmd ./scripts/smoke-check.sh"]
      ]
    ]
  end

  def application do
    []
  end

  defp deps do
    [
      {:nerves, "~> 1.11 or ~> 1.12", runtime: false},
      {:nerves_system_br, "~> 1.33", runtime: false}
    ]
  end

  defp bootstrap(args) do
    Mix.target(:atomcam2)
    Application.ensure_all_started(:nerves_bootstrap)
    Mix.Task.run("loadconfig", args)
  end

  defp nerves_package do
    [
      type: :system,
      platform: Nerves.System.BR,
      platform_config: [
        defconfig: "nerves_defconfig"
      ],
      env: [
        {"TARGET_ARCH", "mipsel"},
        {"TARGET_CPU", "mips32r5"},
        {"TARGET_OS", "linux"},
        {"TARGET_ABI", "gnu"},
        {"TARGET_GCC_FLAGS", "-EL -mips32r5 -mabi=32"}
      ],
      checksum: package_files()
    ]
  end

  defp package do
    [
      files: package_files(),
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp package_files do
    [
      "board",
      "docs",
      "package",
      "patches",
      "rootfs_overlay",
      "scripts",
      "busybox.fragment",
      "Config.in",
      "external.desc",
      "external.mk",
      "fwup.conf",
      "linux-3.10.14.defconfig",
      "mix.exs",
      "nerves_defconfig",
      "README.md",
      "CHANGELOG.md",
      "VERSION"
    ]
  end
end
