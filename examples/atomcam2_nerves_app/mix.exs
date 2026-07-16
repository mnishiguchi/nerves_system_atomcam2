defmodule Atomcam2NervesApp.MixProject do
  use Mix.Project

  @app :atomcam2_nerves_app
  @version "0.1.0"
  @all_targets [:atomcam2]

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.16",
      archives: [nerves_bootstrap: "~> 1.10"],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      releases: [{@app, release()}]
    ]
  end

  def application do
    [
      mod: {Atomcam2NervesApp.Application, []},
      extra_applications: [:logger, :runtime_tools, :inets, :ssl]
    ]
  end

  def cli do
    [preferred_targets: [run: :host, test: :host]]
  end

  defp deps do
    [
      # Dependencies for host and target
      {:nerves, "~> 1.11", runtime: false},
      {:shoehorn, "~> 0.9.0"},
      {:ring_logger, "~> 0.9"},
      {:toolshed, "~> 0.5"},

      # # Dependencies for all targets except :host
      # {:nerves_runtime, "~> 0.13.0", targets: @all_targets},
      # {:nerves_pack, "~> 0.7.0", targets: @all_targets},
      # {:nerves_ssh, "~> 1.2", targets: @all_targets},

      # Minimal target dependencies for the first Wi-Fi + SSH milestone.
      # Avoid :nerves_pack for now because it pulls in :vintage_net_direct and
      # :one_dhcpd, which are not needed for Wi-Fi client mode.
      {:nerves_runtime, "~> 0.13.0", targets: @all_targets},
      {:nerves_ssh, "~> 1.2", targets: @all_targets},
      {:mdns_lite, "~> 0.9", targets: @all_targets},
      {:vintage_net, "~> 0.13", targets: @all_targets},
      {:vintage_net_wifi, "~> 0.12", targets: @all_targets},

      # Dependencies for specific targets
      {:nerves_system_atomcam2, path: "../..", runtime: false, targets: :atomcam2}
    ]
  end

  defp aliases do
    [
      setup: [
        "deps.get",
        "cmd ../../scripts/patch-vintage-net-linux-3.10.sh"
      ]
    ]
  end

  defp release do
    [
      overwrite: true,
      cookie: "#{@app}_cookie",
      include_erts: &Nerves.Release.erts/0,
      steps: [&Nerves.Release.init/1, :assemble],
      strip_beams: [keep: ["Docs"]]
    ]
  end
end
