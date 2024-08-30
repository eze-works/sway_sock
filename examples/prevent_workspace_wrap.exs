# Changing the focused workspace with `workspace next/prev` in sway wraps around.
# For some people, this is annoying; because it prevents spamming one keybinding to get to the first or last workspace.
# Unfortunately, there is not setting to change this: https://github.com/swaywm/sway/issues/6750
#
# Fortunately, we can paper around it via IPC. Here is the approach:
#
# The `workspace` event fires whenever there is a change in the "focused" workspace. Among other things, it has the number of the currently focused workspace, as well as the previous one.
# That information is not enough though; going from workspace 1 -> 4, does not tell you much.
# Was that a wrap around after the user did `workspace prev`? Or did they user just not have workspaces 2, and 3, so `workspace next` skipped them?
# That's where the `binding` event comes in. This fires whenever a binding is pressed and tells you the command that was triggered.
#
# From preliminary testing, it looks like hitting the binding for `workspace next` first sends the `workspace`, then `binding` event.
# 
# So our approach will be as follows:
#
# - Listen for both `workspace` and `binding` events
# - When we get a `workspace` event, figure out if it was a forward (workspace 1 -> 3) or backwards (workspace 3 -> 1) move.
# - When we get the related `binding` event, inspect the command that ran:
#   - If it was `workspace next`, then we expect a forward workspace movement (e.g. 1 -> 3). If it was a backwards movement, that means we wrapped back to the start. So we issue a `workspace prev` command to get us back to the end.
#   - If it was `workspace prev`, then we expect a backwards workspace movement (e.g 3 -> 1). If it was a forward movement, that means we wrapped to the end. So we issue a `workspace next` command to get us back to the start.

Mix.install([
  {:sway_sock, path: "./"}
])

defmodule Main do
  # Handle workspace "focus" events
  def maybe_revert_workspace_change({:workspace, %{"change" => "focus"}} = payload, _state) do
    {:workspace, event} = payload 
    
    current = event["current"]["num"]
    previous = event["old"]["num"]

    cond do
      current > previous -> :forward
      current < previous -> :backward
      true -> :ok
    end
  end

  # Handle binding events
  def maybe_revert_workspace_change({:binding, event}, direction) do
    binding = event["binding"]["command"]

    if direction == :forward and binding == "workspace prev" do
      SwaySock.run_command(:sock, "workspace next")
    end

    if direction == :backward and binding == "workspace next" do
      SwaySock.run_command(:sock, "workspace prev")
    end

    :ok
  end

  # Ignore all other events
  def maybe_revert_workspace_change(_event, state), do: state
end

{:ok, pid} = SwaySock.start_link(:sock)
Process.unlink(pid)

SwaySock.subscribe(:sock, [:workspace, :binding], &Main.maybe_revert_workspace_change/2)
