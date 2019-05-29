defmodule Rabbit.Connection.Server do
  @moduledoc false

  use GenServer

  @opts %{
    name: [type: [:atom, :tuple], required: false],
    uri: [type: :binary, required: false],
    username: [type: :binary, default: "guest", required: false],
    password: [type: :binary, default: "guest", required: false],
    virtual_host: [type: :binary, default: "/", required: false],
    host: [type: :binary, default: "localhost", required: false],
    port: [type: :integer, default: 5672, required: false],
    channel_max: [type: :integer, default: 0, required: false],
    frame_max: [type: :integer, default: 0, required: false],
    heartbeat: [type: :integer, default: 10, required: false],
    connection_timeout: [type: :integer, default: 50_000, required: false],
    ssl_options: [type: [:binary, :atom], default: :none, required: false],
    client_properties: [type: :list, default: [], required: false],
    socket_options: [type: :list, default: [], required: false],
    retry_backoff: [type: :integer, default: 1_000, required: true],
    retry_max_delay: [type: :integer, default: 5_000, required: true]
  }

  @connect_opts [
    :username,
    :password,
    :virtual_host,
    :host,
    :port,
    :channel_max,
    :frame_max,
    :heartbeat,
    :connection_timeout,
    :ssl_options,
    :client_properties,
    :socket_options
  ]

  require Logger

  ################################
  # Public API
  ################################

  @doc false
  def start_link(opts \\ []) do
    server_opts = Keyword.take(opts, [:name])
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc false
  def stop(connection, timeout \\ 5_000) do
    GenServer.stop(connection, :normal, timeout)
  end

  @doc false
  def alive?(connection, timeout \\ 5_000) do
    GenServer.call(connection, :alive?, timeout)
  end

  @doc false
  def subscribe(connection, subscriber \\ nil) do
    subscriber = subscriber || self()
    GenServer.call(connection, {:subscribe, subscriber})
  end

  @doc false
  def unsubscribe(connection, subscriber \\ nil) do
    subscriber = subscriber || self()
    GenServer.call(connection, {:unsubscribe, subscriber})
  end

  ################################
  # GenServer Callbacks
  ################################

  @doc false
  @impl GenServer
  def init(opts) do
    with {:ok, opts} <- connection_init(opts) do
      opts = KeywordValidator.validate!(opts, @opts)
      state = init_state(opts)
      {:ok, state, {:continue, :connect}}
    end
  end

  @doc false
  @impl GenServer
  def handle_continue(:connect, state) do
    case connect(state) do
      {:ok, state} -> {:noreply, state}
      {:error, state} -> {:noreply, state, {:continue, :retry_delay}}
    end
  end

  def handle_continue(:cleanup, %{connection: nil} = state) do
    {:noreply, state, {:continue, :retry_delay}}
  end

  def handle_continue(:cleanup, state) do
    {:noreply, state}
  end

  def handle_continue(:retry_delay, state) do
    state = retry_delay(state)
    {:noreply, state}
  end

  @doc false
  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    state = cleanup(state, pid, reason)
    {:noreply, state, {:continue, :cleanup}}
  end

  def handle_info(:reconnect, state) do
    {:noreply, state, {:continue, :connect}}
  end

  @doc false
  @impl GenServer
  def handle_call(:alive?, _from, state) do
    response = check_alive(state)
    {:reply, response, state}
  end

  def handle_call({:subscribe, subscriber}, _from, state) do
    state = perform_subscribe(state, subscriber)
    {:reply, :ok, state}
  end

  def handle_call({:unsubscribe, subscriber}, _from, state) do
    state = cleanup(state, subscriber, :unsubscribe)
    {:reply, :ok, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    perform_disconnect(state)
  end

  ################################
  # Private API
  ################################

  defp connection_init(opts) do
    {module, opts} = Keyword.pop(opts, :module)

    if Code.ensure_loaded?(module) and function_exported?(module, :init, 1) do
      module.init(opts)
    else
      {:ok, opts}
    end
  end

  defp init_state(opts) do
    %{
      name: Keyword.get(opts, :name, self()),
      connection_opts: Keyword.get(opts, :uri) || Keyword.take(opts, @connect_opts),
      connection: nil,
      monitors: %{},
      subscribers: MapSet.new(),
      retry_attempts: 0,
      retry_backoff: Keyword.get(opts, :retry_backoff),
      retry_max_delay: Keyword.get(opts, :retry_max_delay)
    }
  end

  defp connect(%{connection: nil} = state) do
    case AMQP.Connection.open(state.connection_opts) do
      {:ok, connection} ->
        state = %{state | connection: connection}
        state = monitor(state, connection.pid, :connection)
        publish_connected(state, connection)

        {:ok, state}

      error ->
        log_error(state, error)
        {:error, state}
    end
  end

  defp connect(state) do
    {:ok, state}
  end

  defp perform_disconnect(%{connection: nil} = state) do
    state
  end

  defp perform_disconnect(%{connection: connection} = state) do
    :ok = AMQP.Connection.close(connection)
    publish_disconnected(state, :stopped)
    %{state | connection: nil}
  end

  defp monitor(state, pid, type) do
    unless Map.has_key?(state.monitors, pid) do
      Process.monitor(pid)
      %{state | monitors: Map.put(state.monitors, pid, type)}
    else
      state
    end
  end

  defp cleanup(state, pid, reason) do
    state =
      case Map.get(state.monitors, pid) do
        :connection -> connection_down(state, reason)
        :subscriber -> subscriber_down(state, pid)
        _ -> state
      end

    %{state | monitors: Map.delete(state.monitors, pid)}
  end

  defp connection_down(state, reason) do
    log_error(state, reason)
    publish_disconnected(state, reason)
    %{state | retry_attempts: 0, connection: nil}
  end

  defp subscriber_down(state, pid) do
    %{state | subscribers: MapSet.delete(state.subscribers, pid)}
  end

  defp retry_delay(state) do
    delay = calculate_reconnect_delay(state)
    Process.send_after(self(), :reconnect, delay)
    %{state | retry_attempts: state.retry_attempts + 1}
  end

  defp calculate_reconnect_delay(state) do
    delay = state.retry_backoff * state.retry_attempts

    if delay > state.retry_max_delay do
      state.retry_max_delay
    else
      delay
    end
  end

  defp perform_subscribe(%{connection: nil} = state, subscriber) do
    state = monitor(state, subscriber, :subscriber)
    %{state | subscribers: MapSet.put(state.subscribers, subscriber)}
  end

  defp perform_subscribe(state, subscriber) do
    state = monitor(state, subscriber, :subscriber)
    state = %{state | subscribers: MapSet.put(state.subscribers, subscriber)}
    publish([subscriber], {:connected, state.connection})
    state
  end

  defp check_alive(%{connection: nil}) do
    {:ok, false}
  end

  defp check_alive(_state) do
    {:ok, true}
  end

  defp publish_connected(state_or_subscribers, connection) do
    publish(state_or_subscribers, {:connected, connection})
  end

  defp publish_disconnected(state_or_subscribers, reason) do
    publish(state_or_subscribers, {:disconnected, reason})
  end

  defp publish(%{subscribers: subscribers}, message) do
    publish(subscribers, message)
  end

  defp publish(subscribers, message) do
    for pid <- subscribers do
      if Process.alive?(pid), do: send(pid, message)
    end

    :ok
  end

  defp log_error(state, error) do
    Logger.error("""
    [Rabbit.Connection] #{inspect(state.name)}: connection error.
    Detail: #{inspect(error)}
    """)
  end
end
