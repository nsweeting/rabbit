defmodule Rabbit.Producer.Server do
  @moduledoc false

  use GenServer

  require Logger

  alias Rabbit.Serializer

  @opts %{
    name: [type: [:atom, :tuple], required: false],
    connection: [type: [:atom, :tuple, :pid], required: true],
    serializers: [type: :map, default: Rabbit.Serializer.defaults()],
    publish_opts: [type: :list, default: []]
  }

  ################################
  # Public API
  ################################

  @doc false
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc false
  def publish(producer, exchange, routing_key, payload, opts \\ [], timeout \\ 5_000) do
    GenServer.call(producer, {:publish, exchange, routing_key, payload, opts}, timeout)
  end

  ################################
  # GenServer Callbacks
  ################################

  @doc false
  @impl GenServer
  def init(opts) do
    opts = KeywordValidator.validate!(opts, @opts)
    state = init_state(opts)
    {:ok, state, {:continue, :connection}}
  end

  @doc false
  @impl GenServer
  def handle_continue(:connection, state) do
    case connection(state) do
      {:ok, state} -> {:noreply, state}
      {:error, state} -> {:noreply, state, {:continue, :restart_delay}}
    end
  end

  def handle_continue({:channel, connection}, state) do
    case channel(state, connection) do
      {:ok, state} -> {:noreply, state}
      {:error, state} -> {:noreply, state, {:continue, :restart_delay}}
    end
  end

  def handle_continue(:restart_delay, state) do
    state = restart_delay(state)
    {:noreply, state}
  end

  @doc false
  @impl GenServer
  def handle_call(_msg, _from, %{channel: nil} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call({:publish, exchange, routing_key, payload, opts}, _from, state) do
    result = perform_publish(state, exchange, routing_key, payload, opts)
    {:reply, result, state}
  end

  @doc false
  @impl GenServer
  def handle_info({:connected, connection}, state) do
    {:noreply, state, {:continue, {:channel, connection}}}
  end

  def handle_info({:disconnected, reason}, state) do
    state = channel_down(state, reason)
    {:noreply, state}
  end

  def handle_info(:restart, state) do
    {:noreply, state, {:continue, :connection}}
  end

  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    state = channel_down(state, reason)
    {:noreply, state, {:continue, :restart_delay}}
  end

  ################################
  # Private API
  ################################

  defp init_state(opts) do
    %{
      name: Keyword.get(opts, :name, self()),
      connection: Keyword.get(opts, :connection),
      serializers: Keyword.get(opts, :serializers),
      publish_opts: Keyword.get(opts, :publish_opts),
      channel: nil,
      restart_attempts: 0
    }
  end

  defp connection(state) do
    case Rabbit.Connection.subscribe(state.connection, self()) do
      :ok ->
        {:ok, state}

      {:error, error} ->
        log_error(state, error)
        {:error, state}
    end
  end

  defp channel(%{channel: nil} = state, connection) do
    case AMQP.Channel.open(connection) do
      {:ok, channel} ->
        Process.monitor(channel.pid)
        state = %{state | channel: channel}
        {:ok, state}

      error ->
        log_error(state, error)
        {:error, state}
    end
  end

  defp channel(state, _connection) do
    {:ok, state}
  end

  defp restart_delay(state) do
    restart_attempts = state.restart_attempts + 1
    delay = calculate_delay(restart_attempts)
    Process.send_after(self(), :restart, delay)
    %{state | restart_attempts: restart_attempts}
  end

  defp channel_down(%{channel: nil} = state, _reason) do
    state
  end

  defp channel_down(state, reason) do
    log_error(state, reason)
    %{state | restart_attempts: 0, channel: nil}
  end

  defp calculate_delay(attempt) when attempt > 5 do
    5_000
  end

  defp calculate_delay(attempt) do
    1000 * attempt
  end

  defp perform_publish(state, exchange, routing_key, payload, opts) do
    opts = Keyword.merge(state.publish_opts, opts)

    with {:ok, payload} <- encode_payload(state.serializers, payload, opts) do
      AMQP.Basic.publish(state.channel, exchange, routing_key, payload, opts)
    end
  end

  defp encode_payload(serializers, payload, opts) do
    with {:ok, content_type} when is_binary(content_type) <- Keyword.fetch(opts, :content_type),
         {:ok, serializer} when is_atom(serializer) <- Map.fetch(serializers, content_type) do
      Serializer.encode(serializer, payload)
    else
      :error -> {:ok, payload}
    end
  end

  defp log_error(state, error) do
    Logger.error("""
    #{inspect(state.name)}: producer error.
    Detail: #{inspect(error)}
    """)
  end
end
