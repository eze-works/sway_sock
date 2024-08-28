defmodule SwayIpcTest do
  use ExUnit.Case
  doctest SwayIpc

  test "greets the world" do
    assert SwayIpc.hello() == :world
  end
end
