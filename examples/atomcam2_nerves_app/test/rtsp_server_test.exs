defmodule Atomcam2NervesApp.RtspServerTest do
  use ExUnit.Case, async: true

  alias Atomcam2NervesApp.RtspServer

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "atomcam2-rtsp-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "accepts only one explicit setting" do
    assert RtspServer.parse_config("enabled=true\n") == {:ok, true}
    assert RtspServer.parse_config("enabled=false\n") == {:ok, false}
    assert RtspServer.parse_config("") == {:error, :invalid_config}
    assert RtspServer.parse_config("enabled=yes") == {:error, :invalid_config}
    assert RtspServer.parse_config(" enabled=true\n") == {:error, :invalid_config}
  end

  test "starts once the vendor runtime is running", %{root: root} do
    config_path = Path.join(root, "auto-start.conf")
    File.write!(config_path, "enabled=true\n")

    {:ok, commands} = Agent.start_link(fn -> [] end)
    {:ok, server} = Agent.start_link(fn -> :stopped end)

    start_supervised!(
      {RtspServer,
       name: name(),
       config_path: config_path,
       poll_interval_ms: 60_000,
       command_runner: runner(commands, server),
       vendor_status: fn -> :running end}
    )

    assert_eventually(fn ->
      match?(%{phase: :running, last_result: :started}, RtspServer.status(last_name()))
    end)

    assert Agent.get(commands, & &1) == ["status", "start"]
  end

  test "waits while the vendor runtime is not running", %{root: root} do
    config_path = Path.join(root, "auto-start.conf")
    File.write!(config_path, "enabled=true\n")

    {:ok, commands} = Agent.start_link(fn -> [] end)
    {:ok, server} = Agent.start_link(fn -> :stopped end)

    start_supervised!(
      {RtspServer,
       name: name(),
       config_path: config_path,
       poll_interval_ms: 60_000,
       command_runner: runner(commands, server),
       vendor_status: fn -> :waiting end}
    )

    assert_eventually(fn ->
      match?(%{phase: :waiting, last_result: {:waiting, :waiting}}, RtspServer.status(last_name()))
    end)

    refute "start" in Agent.get(commands, & &1)
  end

  test "stops when the vendor runtime goes away", %{root: root} do
    config_path = Path.join(root, "auto-start.conf")
    File.write!(config_path, "enabled=true\n")

    {:ok, commands} = Agent.start_link(fn -> [] end)
    {:ok, server} = Agent.start_link(fn -> :running end)

    start_supervised!(
      {RtspServer,
       name: name(),
       config_path: config_path,
       poll_interval_ms: 60_000,
       command_runner: runner(commands, server),
       vendor_status: fn -> :failed end}
    )

    assert_eventually(fn ->
      match?(%{phase: :disabled}, RtspServer.status(last_name()))
    end)

    assert "stop" in Agent.get(commands, & &1)
    assert Agent.get(server, & &1) == :stopped
  end

  test "stops when disabled", %{root: root} do
    config_path = Path.join(root, "auto-start.conf")
    File.write!(config_path, "enabled=false\n")

    {:ok, commands} = Agent.start_link(fn -> [] end)
    {:ok, server} = Agent.start_link(fn -> :running end)

    start_supervised!(
      {RtspServer,
       name: name(),
       config_path: config_path,
       poll_interval_ms: 60_000,
       command_runner: runner(commands, server),
       vendor_status: fn -> :running end}
    )

    assert_eventually(fn ->
      match?(%{enabled: false, last_result: :disabled}, RtspServer.status(last_name()))
    end)

    assert "stop" in Agent.get(commands, & &1)
  end

  test "reports a start failure without retrying into a loop", %{root: root} do
    config_path = Path.join(root, "auto-start.conf")
    File.write!(config_path, "enabled=true\n")

    command_runner = fn
      "status" -> {"result=stopped\n", 0}
      "start" -> {"result=failed\nreason=no loopback video device is present\n", 1}
    end

    start_supervised!(
      {RtspServer,
       name: name(),
       config_path: config_path,
       poll_interval_ms: 60_000,
       command_runner: command_runner,
       vendor_status: fn -> :running end}
    )

    assert_eventually(fn ->
      match?(
        %{
          phase: :failed,
          last_result:
            {:start_failed, {:command_failed, 1, "no loopback video device is present"}}
        },
        RtspServer.status(last_name())
      )
    end)
  end

  defp runner(commands, server) do
    fn command ->
      Agent.update(commands, &(&1 ++ [command]))

      case command do
        "status" ->
          {"result=#{Agent.get(server, & &1)}\n", 0}

        "start" ->
          Agent.update(server, fn _ -> :running end)
          {"result=running\n", 0}

        "stop" ->
          Agent.update(server, fn _ -> :stopped end)
          {"result=stopped\n", 0}
      end
    end
  end

  test "keeps stall_strikes at zero while frames advance", %{root: root} do
    config_path = Path.join(root, "auto-start.conf")
    File.write!(config_path, "enabled=true\n")

    {:ok, commands} = Agent.start_link(fn -> [] end)
    {:ok, server} = Agent.start_link(fn -> :running end)
    {:ok, beat} = Agent.start_link(fn -> 0 end)

    start_supervised!(
      {RtspServer,
       name: name(),
       config_path: config_path,
       poll_interval_ms: 60_000,
       command_runner: runner(commands, server),
       vendor_status: fn -> :running end,
       frame_health: fn -> Agent.get_and_update(beat, fn n -> {n, n + 1} end) end}
    )

    for _ <- 1..8 do
      RtspServer.run_now(last_name())
      Process.sleep(5)
    end

    assert %{phase: :running, stall_strikes: 0} = RtspServer.status(last_name())
  end

  test "counts strikes and warns once when frames stall", %{root: root} do
    config_path = Path.join(root, "auto-start.conf")
    File.write!(config_path, "enabled=true\n")

    {:ok, commands} = Agent.start_link(fn -> [] end)
    {:ok, server} = Agent.start_link(fn -> :running end)

    start_supervised!(
      {RtspServer,
       name: name(),
       config_path: config_path,
       poll_interval_ms: 60_000,
       command_runner: runner(commands, server),
       vendor_status: fn -> :running end,
       # Frozen heartbeat: the same value every poll.
       frame_health: fn -> 12_345 end}
    )

    # First poll fires at startup and records the (frozen) beat; drive six more
    # so the stall crosses the warn threshold.
    for _ <- 1..7, do: (RtspServer.run_now(last_name()); Process.sleep(5))

    assert_eventually(fn ->
      match?(%{phase: :running, last_result: {:frame_stall, 6}}, RtspServer.status(last_name()))
    end)

    # A frozen heartbeat never restarts anything — no start/stop is issued.
    refute "start" in Agent.get(commands, & &1)
    refute "stop" in Agent.get(commands, & &1)
  end

  test "recovers stall count when frames resume", %{root: root} do
    config_path = Path.join(root, "auto-start.conf")
    File.write!(config_path, "enabled=true\n")

    {:ok, commands} = Agent.start_link(fn -> [] end)
    {:ok, server} = Agent.start_link(fn -> :running end)
    {:ok, beat} = Agent.start_link(fn -> {:frozen, 7} end)

    start_supervised!(
      {RtspServer,
       name: name(),
       config_path: config_path,
       poll_interval_ms: 60_000,
       command_runner: runner(commands, server),
       vendor_status: fn -> :running end,
       frame_health: fn ->
         case Agent.get(beat, & &1) do
           {:frozen, v} -> v
           {:moving, v} -> Agent.update(beat, fn _ -> {:moving, v + 1} end) && v
         end
       end}
    )

    for _ <- 1..3, do: (RtspServer.run_now(last_name()); Process.sleep(5))
    assert RtspServer.status(last_name()).stall_strikes >= 2

    Agent.update(beat, fn _ -> {:moving, 100} end)
    RtspServer.run_now(last_name())
    Process.sleep(5)
    RtspServer.run_now(last_name())
    Process.sleep(5)

    assert RtspServer.status(last_name()).stall_strikes == 0
  end

  defp name do
    generated = :"rtsp-server-#{System.unique_integer([:positive])}"
    Process.put(:rtsp_server_name, generated)
    generated
  end

  defp last_name, do: Process.get(:rtsp_server_name)

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
