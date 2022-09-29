defmodule Rabbit.Producer.Server do
  @moduledoc false

  use GenServer

  require Logger

  import Rabbit.Utilities

  @opts_schema KeywordValidator.schema!(
                 connection: [is: {:one_of, [:tuple, :pid, :atom]}, required: true],
                 sync_start: [is: :boolean, required: true, default: true],
                 sync_start_delay: [is: :integer, required: true, default: 50],
                 sync_start_max: [is: :integer, required: true, default: 100],
                 publish_opts: [is: :list, default: []],
                 setup_opts: [is: :list, required: false]
               )

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

    with {:ok, opts} <- module.init(:producer, opts),
         {:ok, opts} <- validate_opts(opts, @opts_schema) do
      state = init_state(module, opts)
      state = sync_start(state)
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
  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:disconnect, _from, state) do
    state = disconnect(state)
    {:reply, :ok, state}
  end

  def handle_call({:publish, message}, _from, state) do
    result = publish(state, message)
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

  def handle_info({:EXIT, _pid, reason}, state) do
    state = channel_down(state, reason)
    {:noreply, state, {:continue, :restart_delay}}
  end

  def handle_info(_info, state) do
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    disconnect(state)
  end

  ################################
  # Private API
  ################################

  defp init_state(module, opts) do
    %{
      name: process_name(self()),
      module: module,
      sync_start: Keyword.get(opts, :sync_start),
      sync_start_delay: Keyword.get(opts, :sync_start_delay),
      sync_start_max: Keyword.get(opts, :sync_start_max),
      connection: Keyword.get(opts, :connection),
      connection_subscribed: false,
      channel: nil,
      channel_open: false,
      setup_run: false,
      restart_attempts: 0,
      publish_opts: Keyword.get(opts, :publish_opts),
      setup_opts: Keyword.get(opts, :setup_opts)
    }
  end

  defp sync_start(state, attempt \\ 1)

  defp sync_start(%{sync_start: false} = state, _attempt), do: state

  defp sync_start(%{sync_start_max: max} = state, attempt) when attempt >= max do
    log_error(state, {:error, :sync_start_failed})
    state
  end

  defp sync_start(state, attempt) do
    with {:ok, state} <- connection(state),
         {:ok, connection} <- Rabbit.Connection.fetch(state.connection),
         {:ok, state} <- channel(state, connection),
         {:ok, state} <- handle_setup(state) do
      state
    else
      _ ->
        :timer.sleep(state.sync_start_delay)
        sync_start(state, attempt + 1)
    end
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

  defp disconnect(%{channel_open: false} = state), do: state

  defp disconnect(state) do
    close_channel(state)
    remove_channel(state)
  end

  defp close_channel(%{channel: channel}) do
    if Process.alive?(channel.pid), do: AMQP.Channel.close(channel)
  catch
    _, _ -> :ok
  end

  defp restart_delay(state) do
    restart_attempts = state.restart_attempts + 1
    delay = calculate_delay(restart_attempts)
    Process.send_after(self(), :restart, delay)
    %{state | restart_attempts: restart_attempts}
  end

  defp channel_down(%{channel_open: false} = state, _reason), do: state
  defp channel_down(state, :normal), do: remove_channel(state)

  defp channel_down(state, reason) do
    log_error(state, reason)
    remove_channel(state)
  end

  defp calculate_delay(attempt) when attempt > 5, do: 5_000
  defp calculate_delay(attempt), do: 1000 * attempt

  defp publish(%{channel_open: false}, _msg), do: {:error, :not_connected}

  defp publish(state, {exchange, routing_key, payload, opts}) do
    opts = Keyword.merge(state.publish_opts, opts)

    with {:ok, payload} <- encode_payload(payload, opts) do
      AMQP.Basic.publish(state.channel, exchange, routing_key, payload, opts)
    end
  catch
    error -> {:error, error}
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

  defp remove_channel(state) do
    %{
      state
      | restart_attempts: 0,
        channel: nil,
        channel_open: false,
        connection_subscribed: false,
        setup_run: false
    }
  end

  defp log_error(state, error) do
    Logger.error("""
    [Rabbit.Producer] #{inspect(state.name)}: producer error. Restarting...
    Detail: #{inspect(error)}
    """)
  end
end
