defmodule Atomcam2NervesApp.NasExporter.SFTPTest do
  use ExUnit.Case, async: false

  alias Atomcam2NervesApp.NasExporter.SFTP

  test "expires only valid compact recording dates older than the retention window" do
    today = ~D[2026-07-27]

    assert SFTP.expired_date_directory?("20260706", today, 20)
    refute SFTP.expired_date_directory?("20260707", today, 20)
    refute SFTP.expired_date_directory?("20260727", today, 20)
    refute SFTP.expired_date_directory?("20260230", today, 20)
    refute SFTP.expired_date_directory?("../20260706", today, 20)
  end

  test "supervised transport starts disconnected and disconnects idempotently" do
    start_supervised!(SFTP)

    assert SFTP.status() == %{connected: false, channel_ready: false}
    assert SFTP.disconnect() == :ok
    assert SFTP.status() == %{connected: false, channel_ready: false}
  end
end
