defmodule NervesToolchainAtomcam2 do
  @moduledoc false

  use Nerves.Package.Platform

  @impl Nerves.Package.Platform
  def bootstrap(_package), do: :ok

  @impl Nerves.Package.Platform
  def build_path_link(_package), do: "Use the published Atom Cam 2 toolchain artifact"

  @impl Nerves.Artifact.BuildRunner
  def build(_package, _toolchain, _options) do
    {:error, "Build the Atom Cam 2 toolchain outside Nerves and publish its artifact"}
  end

  @impl Nerves.Artifact.BuildRunner
  def archive(_package, _toolchain, _options) do
    {:error, "Use scripts/release-artifacts.sh to package the Atom Cam 2 toolchain"}
  end

  @impl Nerves.Artifact.BuildRunner
  def clean(_package) do
    {:error, "The Atom Cam 2 toolchain is not built through Nerves"}
  end
end
