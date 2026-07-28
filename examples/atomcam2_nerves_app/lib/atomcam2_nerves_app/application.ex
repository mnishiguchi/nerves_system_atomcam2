defmodule Atomcam2NervesApp.Application do
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    Supervisor.start_link(
      children(),
      strategy: :one_for_one,
      name: Atomcam2NervesApp.Supervisor
    )
  end

  defp children do
    case Application.fetch_env!(:atomcam2_nerves_app, :target) do
      :host ->
        []

      :atomcam2 ->
        :ok = Atomcam2NervesApp.Discovery.advertise()

        [
          Atomcam2NervesApp.TimeSync,
          Atomcam2NervesApp.FirmwareHealth,
          Atomcam2NervesApp.VendorCamera,
          Atomcam2NervesApp.NasExporter.SFTP,
          Atomcam2NervesApp.NasExporter
        ]
    end
  end
end
