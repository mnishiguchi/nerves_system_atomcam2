defmodule Atomcam2NervesApp.Application do
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    :ok = Atomcam2NervesApp.Discovery.advertise()

    children = [Atomcam2NervesApp.TimeSync]

    Supervisor.start_link(children, strategy: :one_for_one, name: Atomcam2NervesApp.Supervisor)
  end
end
