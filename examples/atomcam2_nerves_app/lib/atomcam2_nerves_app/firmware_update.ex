defmodule Atomcam2NervesApp.FirmwareUpdate do
  @moduledoc """
  Guards the unsupported remote firmware update path.

  Atom Cam 2 currently boots from files on a FAT partition that is mounted by
  the running system. Updating that partition through fwup has not been proven
  safe, so application updates must use `mix atomcam2.install` while the camera
  is powered down.
  """

  @spec reject_remote_update() :: {:error, String.t()}
  def reject_remote_update do
    {:error, "Atom Cam 2 remote upload is disabled; use mix atomcam2.install"}
  end
end
