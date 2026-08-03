defmodule Atomcam2NervesApp.BootAnnounce do
  @moduledoc """
  Play the boot announcement once at application startup.

  The work happens in `/usr/bin/atomcam2-boot-announce`: it loads the audio
  kernel modules if nothing loaded them yet, says 「起動しました。」 through
  the speaker, and blinks the blue status LED, leaving it lit. This only
  works because operation is native-only — a running `iCamera_app` would
  hold the IMPAudio lock. The task is fire-and-forget: failures are logged
  and never affect the rest of the supervision tree.
  """

  use Task, restart: :temporary

  require Logger

  @command "/usr/bin/atomcam2-boot-announce"

  @spec start_link(keyword()) :: {:ok, pid()}
  def start_link(_options) do
    Task.start_link(&announce/0)
  end

  defp announce do
    case System.cmd(@command, [], stderr_to_stdout: true) do
      {_output, 0} ->
        Logger.info("boot announcement played")

      {output, status} ->
        Logger.warning(
          "boot announcement failed (#{status}): #{String.trim(output)}"
        )
    end
  rescue
    exception ->
      Logger.warning("boot announcement error: #{Exception.message(exception)}")
  end
end
