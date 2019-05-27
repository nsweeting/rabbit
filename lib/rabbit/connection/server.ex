defmodule Rabbit.Connection.Server do
  @moduledoc false

  use GenServer

  require Logger

  @default_state %{
    name: nil,
    opts: nil,
    connection: nil,
    monitors: %{},
    subscribers: MapSet.new(),
    restart_attempts: 0
  }

  ################################
  # Public API
  ################################

  @doc false
  def start_link(connection, opts \\ [])
      when is_atom(connection) and (is_binary(opts) or is_list(opts)) do
    GenServer.start_link(__MODULE__, {connection, opts}, name: connection)
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
  def init({connection, opts}) do
    with {:ok, opts} <- connection_init(connection, opts) do
      state = %{@default_state | name: connection, opts: opts}
      {:ok, state, {:continue, :connect}}
    end
  end

  @doc false
  @impl GenServer
  def handle_continue(:connect, state) do
    case connect(state) do
      {:ok, state} -> {:noreply, state}
      {:error, state} -> {:noreply, state, {:continue, :restart_delay}}
    end
  end

  def handle_continue(:cleanup, %{connection: nil} = state) do
    {:noreply, state, {:continue, :restart_delay}}
  end

  def handle_continue(:cleanup, state) do
    {:noreply, state}
  end

  def handle_continue(:restart_delay, state) do
    state = restart_delay(state)
    {:noreply, state}
  end

  @doc false
  @impl GenServer
  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    state = cleanup(state, ref, pid, reason)
    {:noreply, state, {:continue, :cleanup}}
  end

  def handle_info(:restart, state) do
    {:noreply, state, {:continue, :connect}}
  end

  @doc false
  @impl GenServer
  def handle_call({:subscribe, subscriber}, _from, state) do
    state = perform_subscribe(state, subscriber)
    {:reply, :ok, state}
  end

  def handle_call({:unsubscribe, subscriber}, _from, state) do
    state = perform_unsubscribe(state, subscriber)
    {:noreply, :ok, state}
  end

  ################################
  # Private API
  ################################

  defp connection_init(connection, opts) do
    if Code.ensure_loaded?(connection) and function_exported?(connection, :init, 1) do
      connection.init(opts)
    else
      {:ok, opts}
    end
  end

  defp connect(%{connection: nil} = state) do
    case AMQP.Connection.open(state.opts) do
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

  defp monitor(state, pid, type) do
    ref = Process.monitor(pid)
    %{state | monitors: Map.put(state.monitors, ref, type)}
  end

  defp cleanup(state, ref, pid, reason) do
    state =
      case Map.get(state.monitors, ref) do
        :connection -> connection_down(state, reason)
        :subscriber -> subscriber_down(state, pid)
        _ -> state
      end

    %{state | monitors: Map.delete(state.monitors, ref)}
  end

  defp connection_down(state, reason) do
    log_error(state, reason)
    publish_disconnected(state, reason)
    %{state | restart_attempts: 0, connection: nil}
  end

  defp subscriber_down(state, pid) do
    %{state | subscribers: MapSet.delete(state.subscribers, pid)}
  end

  defp restart_delay(state) do
    restart_attempts = state.restart_attempts + 1
    delay = calculate_delay(restart_attempts)
    Process.send_after(self(), :restart, delay)
    %{state | restart_attempts: restart_attempts}
  end

  defp calculate_delay(attempt) when attempt > 5 do
    5_000
  end

  defp calculate_delay(attempt) do
    1000 * attempt
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

  defp perform_unsubscribe(state, subscriber) do
    %{state | subscribers: MapSet.delete(state.subscribers, subscriber)}
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
    #{inspect(state.name)}: connection error.
    Detail: #{inspect(error)}
    """)
  end
end
