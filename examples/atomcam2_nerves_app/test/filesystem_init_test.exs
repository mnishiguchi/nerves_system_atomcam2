defmodule Atomcam2NervesApp.FilesystemInitTest do
  use ExUnit.Case, async: true

  alias Atomcam2NervesApp.FilesystemInit

  @initialization_region_size 512 * 256

  describe "classify_initialization_region/1" do
    test "recognizes only an exact all-0xff region as invalidated" do
      initialization_region =
        :binary.copy(<<0xFF>>, @initialization_region_size)

      assert FilesystemInit.classify_initialization_region(initialization_region) ==
               :invalidated
    end

    test "treats non-marker content as an existing filesystem" do
      initialization_region =
        <<
          0x00,
          :binary.copy(<<0xFF>>, @initialization_region_size - 1)::binary
        >>

      assert FilesystemInit.classify_initialization_region(initialization_region) ==
               :existing
    end

    test "treats a short read as unknown" do
      initialization_region =
        :binary.copy(<<0xFF>>, @initialization_region_size - 1)

      assert FilesystemInit.classify_initialization_region(initialization_region) ==
               :unknown
    end

    test "treats a read failure result as unknown" do
      assert FilesystemInit.classify_initialization_region(:eof) == :unknown
    end
  end

  describe "initialization_action/1" do
    test "formats only an explicitly invalidated partition" do
      assert FilesystemInit.initialization_action(:invalidated) == :format

      assert FilesystemInit.initialization_action(:existing) ==
               :mount_or_repair

      assert FilesystemInit.initialization_action(:unknown) ==
               :mount_or_repair

      assert FilesystemInit.initialization_action({:read_error, :eio}) ==
               :mount_or_repair
    end
  end

  describe "repair_action/1" do
    test "retries only after successful filesystem-check statuses" do
      assert FilesystemInit.repair_action(0) == :retry_mount
      assert FilesystemInit.repair_action(1) == :retry_mount

      assert FilesystemInit.repair_action(2) == :reboot_required
      assert FilesystemInit.repair_action(3) == :reboot_required

      assert FilesystemInit.repair_action(4) == :leave_unmounted
      assert FilesystemInit.repair_action(6) == :leave_unmounted
      assert FilesystemInit.repair_action(8) == :leave_unmounted
      assert FilesystemInit.repair_action(255) == :leave_unmounted
      assert FilesystemInit.repair_action(:unexpected) == :leave_unmounted
    end
  end

  test "unwraps the File.open callback result before classifying the marker" do
    marker = :binary.copy(<<0xFF>>, 512 * 256)

    marker_path =
      Path.join(
        System.tmp_dir!(),
        "atomcam2-invalidation-marker-#{System.unique_integer([:positive])}"
      )

    File.write!(marker_path, marker)
    on_exit(fn -> File.rm(marker_path) end)

    read_result =
      File.open(marker_path, [:read, :binary], fn file ->
        IO.binread(file, byte_size(marker))
      end)

    assert {:ok, :invalidated} =
             Atomcam2NervesApp.FilesystemInit.classify_initialization_read_result(read_result)
  end
end
