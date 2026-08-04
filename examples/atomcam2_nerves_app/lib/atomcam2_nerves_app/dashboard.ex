defmodule Atomcam2NervesApp.Dashboard do
  @moduledoc """
  Facade for the status dashboard (see docs/20260803_ダッシュボード_提案書.md).

  The dashboard is off by default; `enable(true)` starts the `:inets`
  httpd (default port 80) serving:

    * `GET /status.json` — the canonical machine-readable state
    * `GET /`            — the same data rendered as HTML
    * `GET /healthz`     — liveness check

  `enable(false)` terminates the whole server: the port closes and no
  dashboard code runs at all. The choice persists across reboots.
  """

  alias Atomcam2NervesApp.Dashboard.Server

  @doc "Enable or disable the dashboard. Persists across reboots."
  @spec enable(boolean()) :: :ok | {:error, term()}
  defdelegate enable(enable), to: Server

  @doc "Whether the dashboard HTTP server is currently running."
  @spec enabled?() :: boolean()
  defdelegate enabled?(), to: Server
end
