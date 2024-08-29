defmodule SwaySock do
  use Supervisor

  @message_types [
    run_command: 0,
    get_workspaces: 1,
    subscribe: 2,
    get_outputs: 3,
    get_tree: 4,
    get_marks: 5,
    get_bar_config: 6,
    get_version: 7,
    get_binding_modes: 8,
    get_config: 9,
    send_tick: 10,
    get_binding_state: 12,
    get_inputs: 100,
    get_seats: 101
  ]

  @event_types [
    workspace: 0x80000000,
    output: 0x80000001,
    mode: 0x80000002,
    window: 0x80000003,
    barconfig_update: 0x80000004,
    binding: 0x80000005,
    shutdown: 0x80000006,
    tick: 0x80000007,
    bar_state_update: 0x80000014,
    input: 0x80000015
  ]

  @impl true
  def init(name) do
    # I start a Task.Supervisor because the `subscribe()` message requires spinning
    # up new Elixir processes, and it would be nice if they were supervised.
    #
    # I start an Agent because I need to store the socket somewhere.
    socket = get_socket()

    children = [
      %{
        id: Agent,
        start: {Agent, :start_link, [fn -> socket end, [name: get_agent_name(name)]]}
      },
      {Task.Supervisor, name: get_task_supervisor_name(name)}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @spec start_link(name :: atom()) :: {:ok, pid()}
  @doc """
  Connects to the Sway socket.  `name` identifies the connection

  Returns a Supervisor used to monitor event subscriptions
  """
  def start_link(name) when is_atom(name) do
    Supervisor.start_link(__MODULE__, name, name: name)
  end

  @doc """
  Closes all resources associated with the Sway connection
  """
  def stop(name) when is_atom(name) do
    Supervisor.stop(name)
  end

  @doc """
  Runs the sway commands in `script` 

  Commands are generally separated by newlines. However, they can also be separated by commas (`,`) or semi-colons (`;`).
  See the sway manual (`man 5 sway`) for more details
  """
  def run_command(conn, script) when is_atom(conn) and is_binary(script) do
    send_and_receive(conn, :run_command, [script])
  end

  @doc """
  Retrieves the list of active workspaces
  """
  def get_workspaces(conn) when is_atom(conn) do
    send_and_receive(conn, :get_workspaces)
  end

  @doc """
  Creates a new linked process that invokes `callback` whenever `event` occurs

  You may subscribe to any of the following events

  `#{@event_types |> Enum.map(fn {t, _} -> ":#{t}" end) |> Enum.join(", ")}`

  Events are described in the sway manual under the "EVENTS" section.
  """
  def subscribe(conn, event, callback)
      when is_atom(conn) and
             is_atom(event) and
             is_function(callback, 1) do
    if not Keyword.has_key?(get_event_types(), event) do
      raise(ArgumentError, "invalid event type '#{event}'")
    end

    pid = self()
    task_supervisor = get_task_supervisor_name(conn)

    Task.Supervisor.start_child(task_supervisor, fn ->
      setup_subscription(pid, event, callback)
    end)

    receive do
      %{"success" => _} = result -> result
      response -> raise("Unexpected response from the sway daemon: #{inspect(response)}")
    end
  end

  # Creates the new socket, subscribes it to `event`, and begin the subscriber loop
  # Reports the result of subscribing back to the parent process.
  defp setup_subscription(parent_pid, event, callback) do
    socket = get_socket()
    type_id = get_message_types()[:subscribe]

    send_message(socket, type_id, :json.encode([event]))

    case recv_message(socket, type_id) do
      %{"success" => true} = result ->
        send(parent_pid, result)

      response ->
        send(parent_pid, response)
        exit(:normal)
    end

    expected_type_id = Keyword.fetch!(get_event_types(), event)
    subscriber_loop(socket, expected_type_id, callback)
  end

  defp subscriber_loop(socket, type_id, callback) do
    payload = recv_message(socket, type_id)
    callback.(payload)
    subscriber_loop(socket, type_id, callback)
  end

  @doc """
  Returns the list of outputs
  """
  def get_outputs(conn) when is_atom(conn) do
    send_and_receive(conn, :get_outputs)
  end

  @doc """
  Returns the JSON representation of sway's node tree
  """
  def get_tree(conn) when is_atom(conn) do
    send_and_receive(conn, :get_tree)
  end

  @doc """
  Returns the currently set marks
  """
  def get_marks(conn) when is_atom(conn) do
    send_and_receive(conn, :get_marks)
  end

  @doc """
  Returns the list of configured bar IDs.

  When `bar_id` is non-empty, this function returns the configuration of the given bar instead. 
  """
  def get_bar_config(conn, bar_id \\ "") when is_atom(conn) and is_binary(bar_id) do
    send_and_receive(conn, :get_bar_config, [bar_id])
  end

  @doc """
  Returns version information about the current sway process
  """
  def get_version(conn) when is_atom(conn) do
    send_and_receive(conn, :get_version)
  end

  @doc """
  Returns a list of configured binding modes
  """
  def get_binding_modes(conn) when is_atom(conn) do
    send_and_receive(conn, :get_binding_modes)
  end

  @doc """
  Returns the contents of the last-loaded sway configuration
  """
  def get_config(conn) when is_atom(conn) do
    send_and_receive(conn, :get_config)
  end

  @doc """
  Sends a TICK event to all clients subscribing to the event to ensure that all events prior to the tick were received.

  If a payload is given, it will be included in the TICK event
  """
  def send_tick(conn, payload \\ "") when is_atom(conn) and is_binary(payload) do
    send_and_receive(conn, :send_tick, [payload])
  end

  @doc """
  Returns the currently active binding mode.
  """
  def get_binding_state(conn) when is_atom(conn) do
    send_and_receive(conn, :get_binding_state)
  end

  @doc """
  Returns a list of the input devices currently available
  """
  def get_inputs(conn) when is_atom(conn) do
    send_and_receive(conn, :get_inputs)
  end

  defp get_message_types() do
    @message_types
  end

  defp get_event_types() do
    @event_types
  end

  # Parse an IPC message from the given socket
  defp parse_message(socket) do
    {:ok, header} = :gen_tcp.recv(socket, 14)

    <<"i3-ipc", len::native-size(32), type::native-size(32)>> =
      header

    {:ok, payload} = :gen_tcp.recv(socket, len)

    {type, payload}
  end

  # Recieves a message of a particular type from the sway IPC socket and interprets it as json
  defp recv_message(socket, type_id) when is_port(socket) and is_integer(type_id) do
    {^type_id, payload} = parse_message(socket)
    :json.decode(payload)
  end

  # Sends a message to the sway IPC socket 
  defp send_message(socket, type_id, payload) when is_port(socket) and is_list(payload) do
    allowed = get_message_types() |> Enum.map(fn {_, t} -> t end)

    if type_id not in allowed do
      raise(ArgumentError, "message type '#{type_id}' is not recognized")
    end

    payload_length = IO.iodata_length(payload)
    msg = ["i3-ipc", <<payload_length::native-size(32)>>, <<type_id::native-size(32)>>, payload]
    :ok = :gen_tcp.send(socket, msg)
  end

  defp send_and_receive(conn, type, payload \\ []) when is_atom(conn) and is_atom(type) do
    socket = Agent.get(get_agent_name(conn), fn socket -> socket end)
    type_id = Keyword.fetch!(get_message_types(), type)
    send_message(socket, type_id, payload)
    recv_message(socket, type_id)
  end

  defp get_socket() do
    path = get_socket_path()
    {:ok, socket} = :gen_tcp.connect({:local, path}, 0, [:local, :binary, {:active, false}])
    socket
  end

  defp get_socket_path() do
    case System.fetch_env("SWAYSOCK") do
      {:ok, path} ->
        path

      :error ->
        case System.cmd("sway", ["--get-socketpath"], stderr_to_stdout: true) do
          {path, 0} -> {:ok, path}
          {err, _status} -> raise(SwaySock.NotFound, err)
        end
    end
  end

  defp get_agent_name(conn) do
    String.to_atom("#{conn}__store")
  end

  defp get_task_supervisor_name(conn) do
    String.to_atom("#{conn}__tasks")
  end
end
