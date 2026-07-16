defmodule Mix.Tasks.Atomcam2.Install do
  use Mix.Task

  @shortdoc "Installs the Atom Cam 2 flat-SD payload"

  @moduledoc """
  Installs the final Atom Cam 2 application payload to a mounted MicroSD card.

      mix atomcam2.install
      mix atomcam2.install --mount /path/to/mounted/sd
      mix atomcam2.install --dry-run

  Without `--mount`, the task uses the mounted filesystem labeled `ATOMCAM2`.
  Existing Atom Cam 2 files are backed up before they are replaced.

  Options:

    - `--mount PATH` - use an explicit mounted FAT partition
    - `--dry-run` - validate and print the planned changes without writing
    - `--no-backup` - replace files without creating a backup
    - `--help` - show this help
  """

  @switches [mount: :string, dry_run: :boolean, backup: :boolean, help: :boolean]
  @aliases [m: :mount, h: :help]

  @impl Mix.Task
  def run(arguments) do
    {options, remaining_arguments} =
      OptionParser.parse!(arguments, strict: @switches, aliases: @aliases)

    cond do
      options[:help] ->
        Mix.shell().info(@moduledoc)

      remaining_arguments != [] ->
        Mix.raise("unexpected arguments: #{Enum.join(remaining_arguments, " ")}")

      true ->
        install(options)
    end
  end

  defp install(options) do
    ensure_atomcam2_target!()

    application_root = Mix.Project.project_file() |> Path.expand() |> Path.dirname()
    repository_root = Path.expand("../..", application_root)
    installer = Path.join(repository_root, "scripts/install-sd-files.sh")
    payload = Path.expand("nerves/images/atomcam2-sd", Mix.Project.build_path())
    mount = options[:mount] || detect_mount!()

    unless File.regular?(installer) do
      Mix.raise("missing Atom Cam 2 installer: #{installer}")
    end

    unless File.dir?(payload) do
      Mix.raise("missing final Atom Cam 2 payload: #{payload}\nRun mix firmware first.")
    end

    installer_arguments =
      ["--source", payload, "--mount", mount, "--force"]
      |> maybe_add_flag(options[:dry_run], "--dry-run")
      |> maybe_add_flag(options[:backup] == false, "--no-backup")

    case System.cmd(installer, installer_arguments,
           cd: repository_root,
           into: IO.stream(),
           stderr_to_stdout: true
         ) do
      {_output, 0} -> :ok
      {_output, status} -> Mix.raise("Atom Cam 2 installation failed with status #{status}")
    end
  end

  defp ensure_atomcam2_target! do
    if Mix.target() != :atomcam2 do
      Mix.raise("mix atomcam2.install requires MIX_TARGET=atomcam2")
    end
  end

  defp detect_mount! do
    findmnt =
      System.find_executable("findmnt") ||
        Mix.raise("findmnt is required for automatic mount detection; pass --mount instead")

    case System.cmd(findmnt, ["-rn", "-S", "LABEL=ATOMCAM2", "-o", "TARGET"],
           stderr_to_stdout: true
         ) do
      {output, status} when status in [0, 1] ->
        output
        |> String.split("\n", trim: true)
        |> Enum.uniq()
        |> select_mount!()

      {output, status} ->
        Mix.raise("could not detect the ATOMCAM2 mount (status #{status}): #{String.trim(output)}")
    end
  end

  defp select_mount!([mount]), do: mount

  defp select_mount!([]) do
    Mix.raise("""
    no mounted filesystem labeled ATOMCAM2 was found
    Mount the MicroSD FAT partition or pass --mount /path/to/mounted/sd.
    """)
  end

  defp select_mount!(mounts) do
    Mix.raise(
      "multiple mounted filesystems labeled ATOMCAM2 were found: #{Enum.join(mounts, ", ")}"
    )
  end

  defp maybe_add_flag(arguments, true, flag), do: arguments ++ [flag]
  defp maybe_add_flag(arguments, _enabled, _flag), do: arguments
end
