defmodule Rabbit.Connection.Server do
  @moduledoc false

  use GenServer

  import Rabbit.Utilities

  require Logger

  @opts_schema %{
    name: [type: [:binary, :atom], required: true, default: :undefined],
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

  @connection_opts [
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
    Process.flag(:trap_exit, true)

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

  def handle_continue(:retry_delay, state) do
    state = retry_delay(state)
    {:noreply, state}
  end

  @doc false
  @impl GenServer
  def handle_info(:reconnect, state) do
    {:noreply, state, {:continue, :connect}}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    state = remove_subscriber(state, pid)
    {:noreply, state}
  end

  def handle_info({:EXIT, _pid, reason}, state) do
    state = connection_down(state, reason)
    {:noreply, state, {:continue, :retry_delay}}
  end

  def handle_info(_info, state) do
    {:noreply, state}
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
    {:reply, state.connection_open, state}
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
      connection_uri: Keyword.get(opts, :uri),
      connection_name: Keyword.get(opts, :name),
      connection_opts: Keyword.take(opts, @connection_opts),
      connection: nil,
      connection_open: false,
      subscribers: MapSet.new(),
      retry_attempts: 0,
      retry_backoff: Keyword.get(opts, :retry_backoff),
      retry_max_delay: Keyword.get(opts, :retry_max_delay)
    }
  end

  defp connect(%{connection_open: true} = state), do: {:ok, state}

  defp connect(state) do
    case do_connect(state) do
      {:ok, connection} ->
        Process.link(connection.pid)
        state = %{state | connection: connection, connection_open: true}
        publish_connected(state, connection)

        {:ok, state}

      error ->
        log_error(state, error)
        {:error, state}
    end
  end

  defp do_connect(%{connection_uri: nil} = state) do
    AMQP.Connection.open(state.connection_opts, state.connection_name)
  end

  defp do_connect(state) do
    AMQP.Connection.open(
      state.connection_uri,
      state.connection_name,
      state.connection_opts
    )
  end

  defp disconnect(%{connection_open: false} = state), do: state

  defp disconnect(%{connection: connection} = state) do
    if Process.alive?(connection.pid), do: AMQP.Connection.close(connection)
    publish_disconnected(state, :stopped)
    remove_connection(state)
  end

  defp fetch(%{connection_open: false}), do: {:error, :not_connected}
  defp fetch(state), do: {:ok, state.connection}

  defp connection_down(%{connection_open: false} = state, _reason), do: state

  defp connection_down(state, reason) do
    log_error(state, reason)
    publish_disconnected(state, reason)
    remove_connection(state)
  end

  defp remove_subscriber(state, pid) do
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

  defp subscribe(%{connection_open: false} = state, subscriber) do
    add_subscriber(state, subscriber)
  end

  defp subscribe(state, subscriber) do
    state = add_subscriber(state, subscriber)
    publish_connected([subscriber], state.connection)
    state
  end

  defp add_subscriber(state, subscriber) do
    if !MapSet.member?(state.subscribers, subscriber) do
      Process.monitor(subscriber)
    end

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

  defp remove_connection(state) do
    %{state | connection: nil, connection_open: false, retry_attempts: 0}
  end

  defp log_error(state, error) do
    Logger.error("""
    [Rabbit.Connection] #{inspect(state.name)}: connection error.
    Detail: #{inspect(error)}
    """)
  end
end
