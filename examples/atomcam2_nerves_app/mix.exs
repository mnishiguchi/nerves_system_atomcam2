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
      archives: [nerves_bootstrap: "~> 1.15"],
      start_permanent: Mix.env() == :prod,
      build_embedded: true,
      deps: deps(),
      releases: [{@app, release()}]
    ]
  end

  def application do
    [
      mod: {Atomcam2NervesApp.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp deps do
    [
      {:nerves, "~> 1.11 or ~> 1.12", runtime: false, targets: @all_targets},
      {:shoehorn, "~> 0.9", targets: @all_targets},
      {:toolshed, "~> 0.4", targets: @all_targets},
      {:ring_logger, "~> 0.11", targets: @all_targets},
      {:nerves_runtime, "~> 0.13", targets: @all_targets},
      {:vintage_net, "~> 0.13", targets: @all_targets},
      {:vintage_net_wifi, "~> 0.12", targets: @all_targets},
      {:mdns_lite, "~> 0.8", targets: @all_targets},
      {:nerves_ssh, "~> 0.5", targets: @all_targets},
      {:nerves_system_atomcam2, path: "../..", runtime: false, targets: :atomcam2}
    ]
  end

  defp release do
    [
      overwrite: true,
      cookie: "atomcam2_nerves_app_cookie"
    ]
  end
end
