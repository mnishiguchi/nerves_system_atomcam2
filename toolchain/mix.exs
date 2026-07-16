defmodule NervesToolchainAtomcam2.MixProject do
  use Mix.Project

  @app :nerves_toolchain_atomcam2
  @version Path.join(__DIR__, "VERSION")
           |> File.read!()
           |> String.trim()
  @source_url "https://github.com/mnishiguchi/nerves_system_atomcam2"

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.16",
      description: "Nerves toolchain for Atom Cam 2",
      source_url: @source_url,
      compilers: compilers(Mix.env()),
      nerves_package: nerves_package(),
      deps: deps()
    ]
  end

  def application, do: []

  defp compilers(:prod), do: [:nerves_package | Mix.compilers()]
  defp compilers(_environment), do: Mix.compilers()

  defp nerves_package do
    [
      type: :toolchain,
      platform: NervesToolchainAtomcam2,
      target_tuple: :mipsel_nerves_linux_musl,
      artifact_sites: [
        {:github_releases, "mnishiguchi/nerves_system_atomcam2"}
      ],
      checksum: checksum_files()
    ]
  end

  defp deps do
    [
      {:nerves, "~> 1.13", runtime: false}
    ]
  end

  defp checksum_files do
    [
      "VERSION",
      "mix.exs",
      "lib"
    ]
  end
end
