defmodule Rabbit.Connection.Server do
  @moduledoc false

  use GenServer

  import Rabbit.Utilities

  require Logger

  @opts_schema %{
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

  ################################
  # Public API
  ################################

  @doc false
  def start_link(module, opts \\ [], server_opts \\ []) do
    GenServer.start_link(__MODULE__, {module, opts}, server_opts)
  end

  ################################
  # GenServer Callbacks
  ################################

  @doc false
  @impl GenServer
  def init({module, opts}) do
    with {:ok, opts} <- module.init(:connection, opts),
         {:ok, opts} <- validate_opts(opts, @opts_schema) do
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
  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:fetch, _from, state) do
    result = fetch(state)
    {:reply, result, state}
  end

  def handle_call(:alive?, _from, state) do
    result = alive?(state)
    {:reply, result, state}
  end

  def handle_call({:subscribe, subscriber}, _from, state) do
    state = subscribe(state, subscriber)
    {:reply, :ok, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    disconnect(state)
  end

  ################################
  # Private API
  ################################

  defp init_state(opts) do
    %{
      name: process_name(self()),
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

  defp disconnect(%{connection: nil} = state) do
    state
  end

  defp disconnect(%{connection: connection} = state) do
    if Process.alive?(connection.pid), do: AMQP.Connection.close(connection)
    publish_disconnected(state, :stopped)
    %{state | connection: nil}
  end

  defp fetch(%{connection: nil}), do: {:error, :not_connected}
  defp fetch(state), do: {:ok, state.connection}

  defp alive?(%{connection: nil}), do: false
  defp alive?(_state), do: true

  defp monitor(state, pid, type) do
    if Map.has_key?(state.monitors, pid) do
      state
    else
      Process.monitor(pid)
      %{state | monitors: Map.put(state.monitors, pid, type)}
    end
  end

  defp cleanup(state, pid, reason) do
    state =
      case Map.get(state.monitors, pid) do
        :connection ->
          log_error(state, reason)
          publish_disconnected(state, reason)
          %{state | retry_attempts: 0, connection: nil}

        :subscriber ->
          %{state | subscribers: MapSet.delete(state.subscribers, pid)}

        _ ->
          state
      end

    %{state | monitors: Map.delete(state.monitors, pid)}
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

  defp subscribe(%{connection: nil} = state, subscriber) do
    state = monitor(state, subscriber, :subscriber)
    %{state | subscribers: MapSet.put(state.subscribers, subscriber)}
  end

  defp subscribe(state, subscriber) do
    state = monitor(state, subscriber, :subscriber)
    publish_connected([subscriber], state.connection)
    %{state | subscribers: MapSet.put(state.subscribers, subscriber)}
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
