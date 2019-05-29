defmodule Rabbit.Consumer.Server do
  @moduledoc false

  use GenServer

  import Rabbit.Utilities

  require Logger

  @opts %{
    name: [type: [:atom, :tuple], required: false],
    module: [custom: [{__MODULE__, :validate}], required: true],
    queue: [type: :binary, required: true],
    serializers: [type: :map, default: Rabbit.Serializer.defaults()],
    prefetch_count: [type: :integer, default: 1],
    prefetch_size: [type: :integer, default: 0],
    consumer_tag: [type: :binary, default: ""],
    no_local: [type: :boolean, default: false],
    no_ack: [type: :boolean, default: false],
    exclusive: [type: :boolean, default: false],
    no_wait: [type: :boolean, default: false],
    arguments: [type: :list, default: []]
  }

  @qos_opts [
    :prefetch_size,
    :prefetch_count,
    :global
  ]
  @consume_opts [
    :consumer_tag,
    :no_local,
    :no_ack,
    :exclusive,
    :no_wait,
    :arguments
  ]
  @worker_opts [
    :serializers,
    :timeout
  ]

  ################################
  # Public API
  ################################

  @doc false
  def child_spec(args) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, args}
    }
  end

  @doc false
  def start_link(connection, opts \\ []) do
    server_opts = Keyword.take(opts, [:name])
    GenServer.start_link(__MODULE__, {connection, opts}, server_opts)
  end

  @doc false
  def stop(consumer, timeout \\ 5_000) do
    GenServer.stop(consumer, :normal, timeout)
  end

  @doc false
  def ack(message, opts \\ []) do
    GenServer.cast(message.consumer, {:ack, message.meta.delivery_tag, opts})
  end

  @doc false
  def nack(message, opts \\ []) do
    GenServer.cast(message.consumer, {:nack, message.meta.delivery_tag, opts})
  end

  @doc false
  def reject(message, opts \\ []) do
    GenServer.cast(message.consumer, {:reject, message.meta.delivery_tag, opts})
  end

  @doc false
  def validate(:module, module) do
    validate_consumer(module)
  end

  ################################
  # GenServer Callbacks
  ################################

  @doc false
  @impl GenServer
  def init({connection, opts}) do
    with {:ok, opts} <- consumer_init(opts) do
      opts = KeywordValidator.validate!(opts, @opts)
      state = init_state(connection, opts)
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
      {:ok, state} -> {:noreply, state, {:continue, :after_connect}}
      {:error, state} -> {:noreply, state, {:continue, :restart_delay}}
    end
  end

  def handle_continue(:after_connect, state) do
    case after_connect(state) do
      {:ok, state} -> {:noreply, state, {:continue, :consume}}
      {:error, state} -> {:noreply, state, {:continue, :restart_delay}}
    end
  end

  def handle_continue(:consume, state) do
    case consume(state) do
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

  def handle_info({:basic_consume_ok, _info}, state) do
    {:noreply, state}
  end

  def handle_info({:basic_deliver, payload, meta}, state) do
    handle_message(state, payload, meta)
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    state = channel_down(state, reason)
    {:noreply, state, {:continue, :restart_delay}}
  end

  @doc false
  @impl GenServer
  def handle_cast({:ack, delivery_tag, opts}, state) do
    perform_ack(state, delivery_tag, opts)
    {:noreply, state}
  end

  def handle_cast({:nack, delivery_tag, opts}, state) do
    perform_nack(state, delivery_tag, opts)
    {:noreply, state}
  end

  def handle_cast({:reject, delivery_tag, opts}, state) do
    perform_reject(state, delivery_tag, opts)
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    disconnect(state)
  end

  ################################
  # Private Helpers
  ################################

  defp consumer_init(opts) do
    module = Keyword.get(opts, :module)

    if callback_exported?(module, :init, 1) do
      module.init(opts)
    else
      {:ok, opts}
    end
  end

  defp init_state(connection, opts) do
    %{
      name: Keyword.get(opts, :name, self()),
      module: Keyword.get(opts, :module),
      connection: connection,
      channel: nil,
      restart_attempts: 0,
      queue: Keyword.get(opts, :queue),
      qos_opts: Keyword.take(opts, @qos_opts),
      consume_opts: Keyword.take(opts, @consume_opts),
      worker_opts: Keyword.take(opts, @worker_opts)
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

  defp after_connect(state) do
    if callback_exported?(state.module, :after_connect, 2) do
      case state.module.after_connect(state.channel, state.queue) do
        :ok ->
          {:ok, state}

        error ->
          log_error(state, error)
          {:error, state}
      end
    else
      {:ok, state}
    end
  end

  defp consume(state) do
    with :ok <- AMQP.Basic.qos(state.channel, state.qos_opts),
         {:ok, _} <- AMQP.Basic.consume(state.channel, state.queue, self(), state.consume_opts) do
      Logger.info("""
      [Rabbit.Consumer] #{inspect(state.name)}: consumer started.
      """)

      {:ok, state}
    else
      error ->
        log_error(state, error)
        {:error, state}
    end
  end

  defp disconnect(%{channel: nil} = state) do
    state
  end

  defp disconnect(%{channel: channel} = state) do
    AMQP.Channel.close(channel)
    state
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

  defp handle_message(state, payload, meta) do
    message = Rabbit.Message.new(state.name, state.module, state.channel, payload, meta)
    Rabbit.Worker.start_child(message, state.worker_opts)
  end

  defp perform_ack(state, delivery_tag, opts) do
    AMQP.Basic.ack(state.channel, delivery_tag, opts)
  end

  defp perform_nack(state, delivery_tag, opts) do
    AMQP.Basic.nack(state.channel, delivery_tag, opts)
  end

  defp perform_reject(state, delivery_tag, opts) do
    AMQP.Basic.reject(state.channel, delivery_tag, opts)
  end

  defp validate_consumer(module) do
    if Code.ensure_loaded?(module) and
         module.module_info[:attributes]
         |> Keyword.get(:behaviour, [])
         |> Enum.member?(Rabbit.Consumer) do
      []
    else
      ["must be a Rabbit.Consumer module"]
    end
  end

  defp log_error(state, error) do
    Logger.error("""
    [Rabbit.Consumer] #{inspect(state.name)}: consumer error.
    Detail: #{inspect(error)}
    """)
  end
end
