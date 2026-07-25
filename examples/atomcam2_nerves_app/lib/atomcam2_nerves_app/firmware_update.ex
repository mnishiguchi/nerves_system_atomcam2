defmodule Atomcam2NervesApp.FirmwareUpdate do
  @moduledoc false

  @update_command "/usr/bin/atomcam2-firmware-update"

  @spec precheck() :: {:ok, keyword()} | {:error, String.t()}
  def precheck do
    case System.cmd(@update_command, ["precheck"], stderr_to_stdout: true) do
      {_output, 0} ->
        {:ok, []}

      {output, _status} ->
        {:error, String.trim(output)}
    end
  rescue
    exception ->
      {:error, Exception.message(exception)}
  end
end
