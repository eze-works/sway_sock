# NOTE:
# These tests must be run in the context of a running sway instance
defmodule SwaySockTest do
  use ExUnit.Case, async: true

  @connection :sway

  def get_connection(), do: @connection

  setup do
    ExUnit.Callbacks.start_link_supervised!({SwaySock, get_connection()})
    :ok
  end

  test "get_workspaces" do
    result = SwaySock.get_workspaces(get_connection())
    assert is_list(result) and length(result) > 0
    assert Map.has_key?(hd(result), "id")
  end

  test "subscribe" do
    # Send a tick event and verify it was received
    # Subscribing to tick event actually generates two events on the listener side

    pid = self()

    # The listener
    SwaySock.subscribe(get_connection(), :tick, fn event ->
      case event do
        # Sent when first subscribing to a tick event
        %{"first" => true} -> send(pid, :first)
        # Sent on subsequent tick events
        %{"first" => false, "payload" => "TOCK"} -> send(pid, :second)
      end
    end)

    SwaySock.send_tick(get_connection(), "TOCK")

    receive do
      :first ->
        receive do
          :second -> true
        after
          3000 -> raise("did not receive second tick event")
        end
    after
      3000 -> raise("did not receive first tick event")
    end
  end

  test "get_outputs" do
    result = SwaySock.get_outputs(get_connection())
    assert is_list(result) and length(result) > 0
    assert Map.has_key?(hd(result), "id")
  end

  test "get_tree" do
    result = SwaySock.get_tree(get_connection())
    assert Map.has_key?(result, "id")
    assert Map.has_key?(result, "nodes")
  end

  test "get_marks" do
    # get a random mark name each test
    mark = for _ <- 1..10, into: "", do: <<Enum.random(?a..?z)>>
    SwaySock.run_command(get_connection(), "mark #{mark}")

    marks = SwaySock.get_marks(get_connection())
    assert marks == [mark]
  end

  test "get_bar_config" do
    result = SwaySock.get_bar_config(get_connection())
    assert is_list(result) and length(result) > 0
    bar = hd(result)
    assert is_binary(bar)

    config = SwaySock.get_bar_config(get_connection(), bar)
    assert Map.has_key?(config, "id")
    assert Map.has_key?(config, "bar_height")
  end

  test "get_version" do
    info = SwaySock.get_version(get_connection())
    assert Map.has_key?(info, "major")
    assert Map.has_key?(info, "minor")
    assert Map.has_key?(info, "patch")
  end

  test "get_binding_modes" do
    modes = SwaySock.get_binding_modes(get_connection())
    assert Enum.member?(modes, "default")
  end

  test "get_config" do
    config = SwaySock.get_config(get_connection())
    assert Map.has_key?(config, "config")
  end

  test "get_binding_state" do
    binding_state = SwaySock.get_binding_state(get_connection())
    assert binding_state == %{"name" => "default"}
  end

  test "get_inputs" do
    inputs = SwaySock.get_inputs(get_connection())
    assert is_list(inputs) and length(inputs) > 0
    assert Map.has_key?(hd(inputs), "identifier")
  end
end
