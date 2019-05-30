defmodule Rabbit.Producer.Server do
  @moduledoc false

  use GenServer

  require Logger

  import Rabbit.Utilities

  @opts %{
    name: [type: [:atom, :tuple], required: false],
    module: [type: :module, required: false],
    connection: [type: [:atom, :tuple, :pid], required: true],
    publish_opts: [type: :list, default: []]
  }

  ################################
  # Public API
  ################################

  @doc false
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  ################################
  # GenServer Callbacks
  ################################

  @doc false
  @impl GenServer
  def init(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    with {:ok, opts} <- producer_init(opts) do
      opts = KeywordValidator.validate!(opts, @opts)
      state = init_state(name, opts)
      {:ok, state, {:continue, :connection}}
    end
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

  @impl GenServer
  def terminate(_reason, state) do
    disconnect(state)
  end

  ################################
  # Private API
  ################################

  defp producer_init(opts) do
    {module, opts} = Keyword.pop(opts, :module)

    if callback_exported?(module, :init, 1) do
      module.init(opts)
    else
      {:ok, opts}
    end
  end

  defp init_state(name, opts) do
    %{
      name: name || self(),
      connection: Keyword.get(opts, :connection),
      publish_opts: Keyword.get(opts, :publish_opts),
      channel: nil,
      restart_attempts: 0
    }
  end

  defp connection(state) do
    try do
      Rabbit.Connection.subscribe(state.connection, self())
      {:ok, state}
    rescue
      error ->
        log_error(state, error)
        {:error, state}
    catch
      msg, reason ->
        log_error(state, {msg, reason})
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

  defp disconnect(%{channel: nil} = state) do
    state
  end

  defp disconnect(%{channel: channel} = state) do
    if Process.alive?(channel.pid), do: AMQP.Channel.close(channel)
    %{state | channel: nil}
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

    with {:ok, payload} <- encode_payload(payload, opts) do
      AMQP.Basic.publish(state.channel, exchange, routing_key, payload, opts)
    end
  end

  defp encode_payload(payload, opts) do
    with {:ok, content_type} when is_binary(content_type) <- Keyword.fetch(opts, :content_type),
         {:ok, serializers} <- Rabbit.Config.get(:serializers),
         {:ok, serializer} when is_atom(serializer) <- Map.fetch(serializers, content_type) do
      Rabbit.Serializer.encode(serializer, payload)
    else
      :error -> {:ok, payload}
    end
  end

  defp log_error(state, error) do
    Logger.error("""
    [Rabbit.Producer] #{inspect(state.name)}: producer error.
    Detail: #{inspect(error)}
    """)
  end
end
