defmodule Rabbit.Consumer.Server do
  @moduledoc false

  use GenServer

  require Logger

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
  def start_link(consumer, connection, opts \\ []) do
    GenServer.start_link(__MODULE__, {consumer, connection, opts}, name: consumer)
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

  ################################
  # GenServer Callbacks
  ################################

  @doc false
  @impl GenServer
  def init({consumer, connection, opts}) do
    state = init_state(consumer, connection, opts)
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

  ################################
  # Private Helpers
  ################################

  defp init_state(consumer, connection, opts) do
    %{
      name: consumer,
      consumer: consumer,
      connection: connection,
      channel: nil,
      restart_attempts: 0,
      worker: Keyword.get(opts, :worker),
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
    case apply(state.consumer, :after_connect, [state.channel, state.queue]) do
      :ok ->
        {:ok, state}

      error ->
        log_error(state, error)
        {:error, state}
    end
  end

  defp consume(state) do
    with :ok <- AMQP.Basic.qos(state.channel, state.qos_opts),
         {:ok, _} <- AMQP.Basic.consume(state.channel, state.queue, self(), state.consume_opts) do
      Logger.info("""
      #{inspect(state.name)}: consumer started.
      """)

      {:ok, state}
    else
      error ->
        log_error(state, error)
        {:error, state}
    end
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
    message = Rabbit.Message.new(state.consumer, state.channel, payload, meta)
    Rabbit.Consumer.WorkerSupervisor.start_child(state.worker, message, state.worker_opts)
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

  defp log_error(state, error) do
    Logger.error("""
    #{inspect(state.name)}: consumer error.
    Detail: #{inspect(error)}
    """)
  end
end
