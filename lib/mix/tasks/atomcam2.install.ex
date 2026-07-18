defmodule Mix.Tasks.Atomcam2.Install do
  use Mix.Task

  @shortdoc "Writes Atom Cam 2 firmware using the Nerves burn task"

  @moduledoc """
  Compatibility wrapper for the standard Nerves `mix burn` task.

      mix atomcam2.install
      mix atomcam2.install --device /dev/sda
      mix atomcam2.install --device /dev/sda -y

  Without `--task`, the standard fwup `complete` task is used.

  New workflows should invoke `mix burn` directly. Arguments are forwarded
  unchanged to that task.
  """

  @impl Mix.Task
  def run(arguments) do
    if arguments in [["--help"], ["-h"]] do
      Mix.shell().info(@moduledoc)
    else
      Mix.shell().info(
        "mix atomcam2.install is deprecated; delegating to mix burn"
      )

      Mix.Task.run("burn", arguments)
    end
  end
end
