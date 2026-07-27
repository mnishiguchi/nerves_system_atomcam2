defmodule Atomcam2NervesApp.NasExporterTest do
  use ExUnit.Case, async: true

  alias Atomcam2NervesApp.NasExporter

  defmodule SuccessfulTransport do
    def export(_config, files) do
      {:ok,
       %{
         uploaded: length(files),
         already_present: 0,
         retained_removed: 0,
         completed_files: files
       }}
    end
  end

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "atomcam2-nas-exporter-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "discovers only finalized vendor recording paths", %{root: root} do
    completed = Path.join(root, "20260727/08/26.mp4")
    wrong_name = Path.join(root, "20260727/08/current.mp4")
    wrong_depth = Path.join(root, "20260727/26.mp4")
    unrelated = Path.join(root, "20260727/08/26.jpg")

    for path <- [completed, wrong_name, wrong_depth, unrelated] do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "recording")
    end

    assert [
             %{
               path: ^completed,
               relative_path: "20260727/08/26.mp4",
               size: 9
             }
           ] = NasExporter.completed_files(root)
  end

  test "ignores symlinks even when their names look like completed recordings", %{root: root} do
    target = Path.join(root, "outside.mp4")
    link = Path.join(root, "20260727/08/26.mp4")

    File.write!(target, "recording")
    File.mkdir_p!(Path.dirname(link))
    File.ln_s!(target, link)

    assert NasExporter.completed_files(root) == []
  end

  test "removes the oldest completed files until the spool is within its limit", %{root: root} do
    paths =
      for relative <- [
            "20260727/08/24.mp4",
            "20260727/08/25.mp4",
            "20260727/08/26.mp4"
          ] do
        path = Path.join(root, relative)
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, String.duplicate("x", 10))
        path
      end

    result =
      root
      |> NasExporter.completed_files()
      |> NasExporter.enforce_spool_limit(20)

    assert result == %{deleted_count: 1, deleted_bytes: 10, remaining_bytes: 20}
    refute File.exists?(Enum.at(paths, 0))
    assert File.exists?(Enum.at(paths, 1))
    assert File.exists?(Enum.at(paths, 2))
  end

  test "marks uploaded files without removing them from mobile playback", %{root: root} do
    spool_path = Path.join(root, "spool")
    marker_path = Path.join(root, "exported")
    config_path = Path.join(root, "nas-export.conf")
    recording_path = Path.join(spool_path, "20260727/08/26.mp4")
    process_name = :"nas-exporter-#{System.unique_integer([:positive])}"

    File.mkdir_p!(Path.dirname(recording_path))
    File.write!(recording_path, "recording")

    File.write!(
      config_path,
      """
      enabled=true
      host=nas.local
      user=atomcam2
      user_dir=#{Path.join(root, "nas-ssh")}
      remote_directory=recordings/atomcam2
      """
    )

    start_supervised!(
      {NasExporter,
       name: process_name,
       config_path: config_path,
       spool_path: spool_path,
       marker_path: marker_path,
       transport: SuccessfulTransport}
    )

    assert_eventually(fn ->
      match?(
        %{last_result: {:ok, %{uploaded: 1}}},
        NasExporter.status(process_name)
      )
    end)

    assert File.read!(Path.join(marker_path, "20260727/08/26.mp4")) == "9\n"
    assert File.exists?(recording_path)
  end

  defp assert_eventually(assertion, attempts \\ 50)

  defp assert_eventually(assertion, attempts) when attempts > 0 do
    if assertion.() do
      :ok
    else
      Process.sleep(10)
      assert_eventually(assertion, attempts - 1)
    end
  end

  defp assert_eventually(_assertion, 0), do: flunk("condition did not become true")
end
