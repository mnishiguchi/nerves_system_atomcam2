defmodule Atomcam2NervesApp.Dashboard.Server do
  @moduledoc """
  Owns the dashboard's `:inets` httpd instance.

  Off by default: the httpd only exists while enabled, so a disabled
  dashboard has no open port, no processes, and no memory cost. The
  enabled/disabled choice is persisted in `#{"/data/atomcam2-dashboard/enabled.conf"}`
  and re-applied at boot (waiting for /data if its filesystem check is
  still running).
  """

  use GenServer

  require Logger

  @config_path "/data/atomcam2-dashboard/enabled.conf"
  @password_path "/data/atomcam2-dashboard/password.conf"
  @default_port 80
  # /data may still be under its filesystem check at boot; poll until the
  # config becomes readable before deciding the initial state.
  @config_poll_ms 10_000

  defstruct httpd_pid: nil

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options \\ []) do
    name = Keyword.get(options, :name, __MODULE__)
    GenServer.start_link(__MODULE__, options, name: name)
  end

  @spec enable(boolean()) :: :ok | {:error, term()}
  def enable(enable) when is_boolean(enable) do
    GenServer.call(__MODULE__, {:enable, enable})
  end

  @spec enabled?() :: boolean()
  def enabled?, do: GenServer.call(__MODULE__, :enabled?)

  @spec set_password(String.t() | nil) :: :ok | {:error, term()}
  def set_password(nil) do
    case File.rm(@password_path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, _reason} = error -> error
    end
  end

  def set_password(password) when is_binary(password) and password != "" do
    with :ok <- File.mkdir_p(Path.dirname(@password_path)),
         :ok <- File.write(@password_path, password) do
      File.chmod(@password_path, 0o600)
    end
  end

  @doc false
  @spec password_valid?(String.t()) :: boolean()
  def password_valid?(candidate) when is_binary(candidate) do
    case File.read(@password_path) do
      {:ok, password} when password != "" ->
        :crypto.hash(:sha256, candidate) == :crypto.hash(:sha256, password)

      _other ->
        false
    end
  end

  @impl GenServer
  def init(_options) do
    send(self(), :apply_config)
    {:ok, %__MODULE__{}}
  end

  @impl GenServer
  def handle_call({:enable, enable}, _from, state) do
    with :ok <- File.mkdir_p(Path.dirname(@config_path)),
         :ok <- File.write(@config_path, "enabled=#{enable}\n") do
      {:reply, :ok, apply_enabled(state, enable)}
    else
      {:error, _reason} = error -> {:reply, error, state}
    end
  end

  def handle_call(:enabled?, _from, state) do
    {:reply, state.httpd_pid != nil, state}
  end

  @impl GenServer
  def handle_info(:apply_config, state) do
    case File.read(@config_path) do
      {:ok, contents} ->
        {:noreply, apply_enabled(state, String.trim(contents) == "enabled=true")}

      {:error, :enoent} ->
        # No configuration: the default is off. Nothing to do.
        {:noreply, state}

      {:error, _reason} ->
        # /data is likely not mounted yet; try again shortly.
        Process.send_after(self(), :apply_config, @config_poll_ms)
        {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp apply_enabled(%{httpd_pid: nil} = state, true) do
    case start_httpd() do
      {:ok, pid} ->
        Logger.info("Dashboard started on port #{port()}")
        %{state | httpd_pid: pid}

      {:error, reason} ->
        Logger.warning("Dashboard start failed: #{inspect(reason)}")
        state
    end
  end

  defp apply_enabled(%{httpd_pid: pid} = state, false) when is_pid(pid) do
    :inets.stop(:httpd, pid)
    Logger.info("Dashboard stopped")
    %{state | httpd_pid: nil}
  end

  defp apply_enabled(state, _no_change), do: state

  defp start_httpd do
    :inets.start(:httpd,
      port: port(),
      bind_address: :any,
      server_name: ~c"atomcam2",
      server_root: ~c"/tmp",
      document_root: ~c"/tmp",
      modules: [Atomcam2NervesApp.Dashboard.Router]
    )
  end

  defp port do
    :atomcam2_nerves_app
    |> Application.get_env(:dashboard, [])
    |> Keyword.get(:port, @default_port)
  end
end
