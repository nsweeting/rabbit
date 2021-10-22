defmodule Rabbit.Consumer.Server do
  @moduledoc false

  use GenServer

  import Rabbit.Utilities

  require Logger

  alias Rabbit.Consumer.Worker

  @opts_schema %{
    connection: [type: [:tuple, :pid, :atom], required: true],
    queue: [type: :binary, required: false],
    prefetch_count: [type: :integer, default: 1],
    prefetch_size: [type: :integer, default: 0],
    consumer_tag: [type: :binary, default: ""],
    no_local: [type: :boolean, default: false],
    no_ack: [type: :boolean, default: false],
    exclusive: [type: :boolean, default: false],
    nowait: [type: :boolean, default: false],
    arguments: [type: :list, default: []],
    timeout: [type: [:integer, :atom], required: false],
    custom_meta: [type: :map, default: %{}],
    setup_opts: [type: :list, default: [], required: false]
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
    :nowait,
    :arguments
  ]
  @worker_opts [
    :timeout
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

    with {:ok, opts} <- module.init(:consumer, opts),
         {:ok, opts} <- validate_opts(opts, @opts_schema) do
      state = init_state(module, opts)
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
      {:ok, state} -> {:noreply, state, {:continue, :setup}}
      {:error, state} -> {:noreply, state, {:continue, :restart_delay}}
    end
  end

  def handle_continue(:setup, state) do
    case handle_setup(state) do
      {:ok, state} -> {:noreply, state, {:continue, :consume}}
      {:error, state} -> {:noreply, state, {:continue, :restart_delay}}
    end
  end

  def handle_continue(:consume, state) do
    case consume(state) do
      {:ok, state} -> {:noreply, state}
      {:error, :no_queue_given} -> {:stop, :no_queue_given, state}
      {:error, state} -> {:noreply, state, {:continue, :restart_delay}}
    end
  end

  def handle_continue(:restart_delay, state) do
    state = restart_delay(state)
    {:noreply, state}
  end

  @doc false
  @impl GenServer
  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  @doc false
  @impl GenServer
  def handle_info({:connected, connection}, state) do
    {:noreply, state, {:continue, {:channel, connection}}}
  end

  def handle_info({:disconnected, reason}, state) do
    state = disconnect(state, reason)
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

  def handle_info({:basic_cancel, _} = error, state) do
    state = disconnect(state, error)
    {:noreply, state, {:continue, :restart_delay}}
  end

  def handle_info({:EXIT, _, _} = exit_msg, state) do
    state = disconnect(state, exit_msg)
    {:noreply, state, {:continue, :restart_delay}}
  end

  def handle_info(_info, state) do
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    disconnect(state)

    Logger.info("""
    [Rabbit.Consumer] #{inspect(state.name)}: consumer #{state.consumer_tag} terminating.
    """)

    :ok
  end

  ################################
  # Private API
  ################################

  defp init_state(module, opts) do
    %{
      name: process_name(self()),
      module: module,
      connection: Keyword.get(opts, :connection),
      connection_subscribed: false,
      channel: nil,
      channel_open: false,
      setup_run: false,
      consuming: false,
      worker: nil,
      worker_started: false,
      consumer_tag: nil,
      restart_attempts: 0,
      queue: Keyword.get(opts, :queue),
      qos_opts: Keyword.take(opts, @qos_opts),
      consume_opts: Keyword.take(opts, @consume_opts),
      worker_opts: Keyword.take(opts, @worker_opts),
      custom_meta: Keyword.get(opts, :custom_meta),
      setup_opts: Keyword.get(opts, :setup_opts)
    }
  end

  defp connection(%{connection_subscribed: true} = state), do: {:ok, state}

  defp connection(state) do
    Rabbit.Connection.subscribe(state.connection, self())
    state = %{state | connection_subscribed: true}
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

  defp channel(%{channel_open: true} = state, _connection), do: {:ok, state}

  defp channel(state, connection) do
    case AMQP.Channel.open(connection) do
      {:ok, channel} ->
        Process.link(channel.pid)
        state = %{state | channel: channel, channel_open: true}
        {:ok, state}

      error ->
        log_error(state, error)
        {:error, state}
    end
  end

  defp handle_setup(%{setup_run: true} = state), do: {:ok, state}

  defp handle_setup(state) do
    if function_exported?(state.module, :handle_setup, 1) do
      case state.module.handle_setup(state) do
        :ok ->
          state = %{state | setup_run: true}
          {:ok, state}

        {:ok, state} ->
          state = %{state | setup_run: true}
          {:ok, state}

        error ->
          log_error(state, error)
          {:error, state}
      end
    else
      {:ok, state}
    end
  end

  defp consume(%{consuming: true} = state), do: {:ok, state}
  defp consume(%{queue: nil}), do: {:error, :no_queue_given}

  defp consume(state) do
    with :ok <- AMQP.Basic.qos(state.channel, state.qos_opts),
         {:ok, tag} <- AMQP.Basic.consume(state.channel, state.queue, self(), state.consume_opts) do
      Logger.info("""
      [Rabbit.Consumer] #{inspect(state.name)}: consumer #{tag} started.
      """)

      state = start_worker(state)
      state = %{state | consuming: true, consumer_tag: tag}
      {:ok, state}
    else
      error ->
        log_error(state, error)
        {:error, state}
    end
  end

  defp start_worker(%{worker_started: true} = state), do: state

  defp start_worker(%{worker_started: false} = state) do
    {:ok, worker} = Worker.start_link()
    %{state | worker_started: true, worker: worker}
  end

  defp disconnect(state, error \\ nil)
  defp disconnect(%{channel_open: false} = state, _error), do: state

  defp disconnect(state, error) do
    if error do
      log_error(state, error)
    end

    state
    |> stop_worker()
    |> close_channel()
  end

  defp close_channel(state) do
    if Process.alive?(state.channel.pid) do
      Process.unlink(state.channel.pid)

      try do
        AMQP.Channel.close(state.channel)
      catch
        _, _ -> :ok
      end
    end

    %{
      state
      | restart_attempts: 0,
        connection_subscribed: false,
        channel: nil,
        channel_open: false,
        consuming: false,
        consumer_tag: nil,
        setup_run: false
    }
  end

  defp restart_delay(state) do
    restart_attempts = state.restart_attempts + 1
    delay = calculate_delay(restart_attempts)
    Process.send_after(self(), :restart, delay)
    %{state | restart_attempts: restart_attempts}
  end

  defp calculate_delay(attempt) when attempt > 5, do: 5_000
  defp calculate_delay(attempt), do: 1000 * attempt

  defp handle_message(state, payload, meta) do
    message =
      Rabbit.Message.new(
        state.name,
        state.module,
        state.channel,
        payload,
        meta,
        state.custom_meta
      )

    Worker.start_child(state.worker, message, state.worker_opts)
  end

  defp stop_worker(state) do
    if is_pid(state.worker) and Process.alive?(state.worker) do
      try do
        :ok = Worker.stop(state.worker)
      catch
        _, _ -> :ok
      end
    end

    %{state | worker: nil, worker_started: false}
  end

  defp log_error(state, error) do
    Logger.error("""
    [Rabbit.Consumer] #{inspect(state.name)}: consumer error.
    Detail: #{inspect(error)}
    """)
  end
end
