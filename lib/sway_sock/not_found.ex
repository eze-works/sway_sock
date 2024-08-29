defmodule SwaySock.NotFound do
  @moduledoc """
  An exception raised when Sway's IPC socket cannot be found
  """
  defexception message: "Could not find sway IPC socket."
end
