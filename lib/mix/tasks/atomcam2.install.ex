defmodule Mix.Tasks.Atomcam2.Install do
  use Mix.Task

  @firmware_metadata_fields [
    {"meta-product", "nerves_fw_product"},
    {"meta-version", "nerves_fw_version"},
    {"meta-uuid", "nerves_fw_uuid"},
    {"meta-platform", "nerves_fw_platform"},
    {"meta-architecture", "nerves_fw_architecture"}
  ]

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

    system_root = Path.expand("../../..", __DIR__)
    installer = Path.join(system_root, "scripts/install-sd-files.sh")
    images_path = Path.expand("nerves/images", Mix.Project.build_path())
    payload = Path.join(images_path, "atomcam2-sd")
    firmware = Path.join(images_path, "#{Mix.Project.config()[:app]}.fw")
    metadata_file = Path.join(payload, "nerves-firmware-metadata.conf")
    mount = options[:mount] || detect_mount!()

    unless File.regular?(installer) do
      Mix.raise("missing Atom Cam 2 installer: #{installer}")
    end

    unless File.dir?(payload) do
      Mix.raise("missing final Atom Cam 2 payload: #{payload}\nRun mix firmware first.")
    end

    unless File.regular?(firmware) do
      Mix.raise("missing Atom Cam 2 firmware: #{firmware}\nRun mix firmware first.")
    end

    write_firmware_metadata!(firmware, metadata_file)

    installer_arguments =
      ["--source", payload, "--mount", mount, "--force"]
      |> maybe_add_flag(options[:dry_run], "--dry-run")
      |> maybe_add_flag(options[:backup] == false, "--no-backup")

    case System.cmd(installer, installer_arguments,
           cd: system_root,
           into: IO.stream(),
           stderr_to_stdout: true
         ) do
      {_output, 0} -> :ok
      {_output, status} -> Mix.raise("Atom Cam 2 installation failed with status #{status}")
    end
  end

  defp write_firmware_metadata!(firmware, metadata_file) do
    fwup =
      System.find_executable("fwup") ||
        Mix.raise("fwup is required to read firmware metadata")

    metadata =
      case System.cmd(fwup, ["-m", "-i", firmware], stderr_to_stdout: true) do
        {output, 0} ->
          parse_firmware_metadata(output)

        {output, status} ->
          Mix.raise("could not read firmware metadata (status #{status}): #{String.trim(output)}")
      end

    lines =
      ["nerves_fw_active=a"] ++
        Enum.map(@firmware_metadata_fields, fn {fwup_key, kv_key} ->
          "a.#{kv_key}=#{firmware_metadata_value!(metadata, fwup_key)}"
        end)

    File.write!(metadata_file, Enum.join(lines, "\n") <> "\n")
    Mix.shell().info("Generated firmware metadata: #{metadata_file}")
  end

  defp parse_firmware_metadata(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.filter(&String.starts_with?(&1, "meta-"))
    |> Map.new(fn line ->
      case String.split(line, "=", parts: 2) do
        [key, value] ->
          {key, value |> String.trim() |> String.trim(~s("))}

        _ ->
          Mix.raise("invalid fwup metadata line: #{inspect(line)}")
      end
    end)
  end

  defp firmware_metadata_value!(metadata, key) do
    case Map.fetch(metadata, key) do
      {:ok, value} when value != "" ->
        value

      _ ->
        Mix.raise("firmware metadata does not contain #{key}")
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
        Mix.raise(
          "could not detect the ATOMCAM2 mount (status #{status}): #{String.trim(output)}"
        )
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
