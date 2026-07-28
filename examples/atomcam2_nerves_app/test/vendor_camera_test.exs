defmodule Atomcam2NervesApp.VendorCameraTest do
  use ExUnit.Case, async: true

  alias Atomcam2NervesApp.VendorCamera

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "atomcam2-vendor-camera-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "accepts only one explicit setting" do
    assert VendorCamera.parse_config("enabled=true\n") == {:ok, true}
    assert VendorCamera.parse_config("enabled=false\n") == {:ok, false}
    assert VendorCamera.parse_config("") == {:error, :invalid_config}
    assert VendorCamera.parse_config("enabled=yes") == {:error, :invalid_config}
    assert VendorCamera.parse_config(" enabled=true\n") == {:error, :invalid_config}
    assert VendorCamera.parse_config("enabled=true \n") == {:error, :invalid_config}

    assert VendorCamera.parse_config("enabled=true\nextra=true") ==
             {:error, :invalid_config}
  end

  test "starts once when explicitly enabled and ready", %{root: root} do
    config_path = Path.join(root, "auto-start.conf")
    File.write!(config_path, "enabled=true\n")

    {:ok, commands} = Agent.start_link(fn -> [] end)
    {:ok, runtime} = Agent.start_link(fn -> :stopped end)

    command_runner = fn command ->
      Agent.update(commands, &(&1 ++ [command]))

      case command do
        "status" ->
          result = Agent.get(runtime, & &1)
          {"result=#{result}\n", 0}

        "precheck" ->
          {"result=ready_for_manual_camera_start\n", 0}

        "start" ->
          Agent.update(runtime, fn _state -> :running end)
          {"result=started\n", 0}
      end
    end

    name = :"vendor-camera-#{System.unique_integer([:positive])}"

    start_supervised!(
      {VendorCamera,
       name: name,
       config_path: config_path,
       poll_interval_ms: 60_000,
       command_runner: command_runner,
       readiness: fn -> :ready end}
    )

    assert_eventually(fn ->
      match?(
        %{phase: :running, start_attempts: 1, last_result: :started},
        VendorCamera.status(name)
      )
    end)

    assert Agent.get(commands, & &1) == ["status", "precheck", "start", "status"]
  end

  test "waits without consuming its start attempt", %{root: root} do
    config_path = Path.join(root, "auto-start.conf")
    File.write!(config_path, "enabled=true\n")

    {:ok, commands} = Agent.start_link(fn -> [] end)

    command_runner = fn "status" ->
      Agent.update(commands, &(&1 ++ ["status"]))
      {"result=stopped\n", 0}
    end

    name = :"vendor-camera-#{System.unique_integer([:positive])}"

    start_supervised!(
      {VendorCamera,
       name: name,
       config_path: config_path,
       poll_interval_ms: 60_000,
       command_runner: command_runner,
       readiness: fn -> {:waiting, [:internet_connection]} end}
    )

    assert_eventually(fn ->
      match?(
        %{
          phase: :waiting,
          start_attempts: 0,
          last_result: {:waiting, [:internet_connection]}
        },
        VendorCamera.status(name)
      )
    end)

    assert Agent.get(commands, & &1) == ["status"]
  end

  test "does not retry a failed start during the same boot", %{root: root} do
    config_path = Path.join(root, "auto-start.conf")
    File.write!(config_path, "enabled=true\n")

    {:ok, commands} = Agent.start_link(fn -> [] end)

    command_runner = fn command ->
      Agent.update(commands, &(&1 ++ [command]))

      case command do
        "status" -> {"result=stopped\n", 0}
        "precheck" -> {"result=ready_for_manual_camera_start\n", 0}
        "start" -> {"start failed\n", 1}
      end
    end

    name = :"vendor-camera-#{System.unique_integer([:positive])}"

    start_supervised!(
      {VendorCamera,
       name: name,
       config_path: config_path,
       poll_interval_ms: 60_000,
       command_runner: command_runner,
       readiness: fn -> :ready end}
    )

    assert_eventually(fn ->
      match?(
        %{phase: :failed, start_attempts: 1},
        VendorCamera.status(name)
      )
    end)

    VendorCamera.run_now(name)

    assert_eventually(fn ->
      VendorCamera.status(name).last_result == :start_attempt_limit
    end)

    assert Agent.get(commands, & &1) == ["status", "precheck", "start", "status"]
  end

  test "missing configuration remains dormant", %{root: root} do
    {:ok, commands} = Agent.start_link(fn -> [] end)

    name = :"vendor-camera-#{System.unique_integer([:positive])}"

    start_supervised!(
      {VendorCamera,
       name: name,
       config_path: Path.join(root, "missing.conf"),
       poll_interval_ms: 60_000,
       command_runner: fn command ->
         Agent.update(commands, &(&1 ++ [command]))
         {"result=stopped\n", 0}
       end,
       readiness: fn -> :ready end}
    )

    assert_eventually(fn ->
      match?(
        %{enabled: false, phase: :disabled, last_result: :not_configured},
        VendorCamera.status(name)
      )
    end)

    assert Agent.get(commands, & &1) == []
  end

  test "keeps a command-runner exit inside the worker", %{root: root} do
    config_path = Path.join(root, "auto-start.conf")
    File.write!(config_path, "enabled=true\n")

    name = :"vendor-camera-#{System.unique_integer([:positive])}"

    pid =
      start_supervised!(
        {VendorCamera,
         name: name,
         config_path: config_path,
         poll_interval_ms: 60_000,
         command_runner: fn "status" -> exit(:epipe) end,
         readiness: fn -> :ready end}
      )

    assert_eventually(fn ->
      match?(
        %{
          phase: :failed,
          start_attempts: 0,
          last_result: {:unexpected_exit, {:exit, :epipe}}
        },
        VendorCamera.status(name)
      )
    end)

    assert Process.alive?(pid)
  end

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
