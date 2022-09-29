defmodule Rabbit.Topology.Server do
  @moduledoc false

  use GenServer

  import Rabbit.Utilities

  require Logger

  @exchange_schema KeywordValidator.schema!(
                     name: [is: :binary, required: true],
                     type: [is: :atom, required: true, default: :direct],
                     durable: [is: :boolean, required: true, default: false],
                     passive: [is: :boolean, required: true, default: false],
                     auto_delete: [is: :boolean, required: true, default: false],
                     internal: [is: :boolean, required: true, default: false],
                     nowait: [is: :boolean, required: true, default: false],
                     arguments: [is: :list, required: true, default: []]
                   )
  @exchange_opts [:durable, :passive, :auto_delete, :internal, :nowait, :arguments]
  @queue_schema KeywordValidator.schema!(
                  name: [is: :binary, required: true],
                  durable: [is: :boolean, required: true, default: false],
                  auto_delete: [is: :boolean, required: true, default: false],
                  exclusive: [is: :boolean, required: true, default: false],
                  passive: [is: :boolean, required: true, default: false],
                  nowait: [is: :boolean, required: true, default: false],
                  arguments: [is: :list, required: true, default: []]
                )
  @queue_opts [:durable, :passive, :auto_delete, :exclusive, :nowait, :arguments]
  @binding_schema KeywordValidator.schema!(
                    type: [is: {:in, [:queue, :exchange]}, required: true],
                    source: [is: :binary, required: true],
                    destination: [is: :binary, required: true],
                    routing_key: [is: :binary, required: true, default: ""],
                    nowait: [is: :boolean, required: true, default: false],
                    arguments: [is: :list, required: true, default: []]
                  )
  @binding_opts [:routing_key, :nowait, :arguments]
  @opts_schema KeywordValidator.schema!(
                 connection: [is: {:one_of, [:tuple, :pid, :atom]}, required: true],
                 retry_delay: [is: :integer, required: true, default: 100],
                 retry_max: [is: :integer, required: true, default: 25],
                 exchanges: [
                   is: {:list, {:keyword, @exchange_schema}},
                   required: true,
                   default: []
                 ],
                 queues: [is: {:list, {:keyword, @queue_schema}}, required: true, default: []],
                 bindings: [is: {:list, {:keyword, @binding_schema}}, required: true, default: []]
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
    with {:ok, opts} <- module.init(:topology, opts),
         {:ok, opts} <- validate_opts(opts, @opts_schema) do
      state = init_state(opts)
      setup_topology(state)
    end
  end

  ################################
  # Private API
  ################################

  defp init_state(opts) do
    Enum.into(opts, %{})
  end

  defp setup_topology(state) do
    with {:ok, connection} <- connection(state),
         {:ok, channel} <- channel(state, connection),
         :ok <- declare_exchanges(state.exchanges, channel),
         :ok <- declare_queues(state.queues, channel),
         :ok <- declare_bindings(state.bindings, channel) do
      :ok = AMQP.Channel.close(channel)
      {:ok, state}
    end
  end

  defp connection(state, attempt \\ 1) do
    if attempt <= state.retry_max do
      case Rabbit.Connection.fetch(state.connection) do
        {:ok, _} = success ->
          success

        {:error, _} ->
          :timer.sleep(state.retry_delay)
          connection(state, attempt + 1)
      end
    else
      {:stop, :no_connection}
    end
  end

  defp channel(state, connection, attempt \\ 1) do
    if attempt <= state.retry_max do
      case AMQP.Channel.open(connection) do
        {:ok, channel} = success ->
          Process.link(channel.pid)
          success

        {:error, _} ->
          :timer.sleep(state.retry_delay)
          channel(state, connection, attempt + 1)
      end
    else
      {:stop, :no_channel}
    end
  end

  defp declare_exchanges([], _channel), do: :ok

  defp declare_exchanges([exchange | exchanges], channel) do
    name = Keyword.get(exchange, :name)
    type = Keyword.get(exchange, :type)
    opts = Keyword.take(exchange, @exchange_opts)

    case AMQP.Exchange.declare(channel, name, type, opts) do
      :ok ->
        declare_exchanges(exchanges, channel)

      error ->
        log_error(error)
        error
    end
  end

  defp declare_queues([], _channel), do: :ok

  defp declare_queues([queue | queues], channel) do
    name = Keyword.get(queue, :name)
    opts = Keyword.take(queue, @queue_opts)

    case AMQP.Queue.declare(channel, name, opts) do
      {:ok, _} ->
        declare_queues(queues, channel)

      error ->
        log_error(error)
        error
    end
  end

  defp declare_bindings([], _channel), do: :ok

  defp declare_bindings([binding | bindings], channel) do
    type = Keyword.get(binding, :type)
    source = Keyword.get(binding, :source)
    destination = Keyword.get(binding, :destination)
    opts = Keyword.take(binding, @binding_opts)

    with :ok <- declare_binding(channel, type, source, destination, opts) do
      declare_bindings(bindings, channel)
    end
  end

  defp declare_binding(channel, :exchange, source, destination, opts) do
    case AMQP.Exchange.bind(channel, destination, source, opts) do
      :ok ->
        :ok

      error ->
        log_error(error)
        error
    end
  end

  defp declare_binding(channel, :queue, source, destination, opts) do
    case AMQP.Queue.bind(channel, destination, source, opts) do
      :ok ->
        :ok

      error ->
        log_error(error)
        error
    end
  end

  defp log_error(error) do
    Logger.error("""
    [Rabbit.Topology] #{inspect(process_name(self()))}: setup error. Restarting...
    Detail: #{inspect(error)}
    """)
  end
end
