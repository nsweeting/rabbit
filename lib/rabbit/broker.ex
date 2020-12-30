defmodule Rabbit.Broker do
  @moduledoc """
  A RabbitMQ broker process.

  The broker is a `Supervisor` that encapsulates all the smaller pieces available
  in Rabbit into a single entity. It provides the following:

  * Durable connection pooling through `Rabbit.Connection`.
  * Automatic broker configuration through `Rabbit.Topology`.
  * Simple message publishing through `Rabbit.Producer`.
  * Simple message consumption through `Rabbit.ConsumerSupervisor`.

  It's recommended that the documentation for each of these components is read
  when utilizing the broker process.

  Be aware that the connection for each component of the broker is automatically
  configured to use the connection process created by the broker. You dont need
  to configure this yourself.

  ## Example

      defmodule MyBroker do
        use Rabbit.Broker

        def start_link(opts \\ []) do
          Rabbit.Broker.start_link(__MODULE__, opts, name: __MODULE__)
        end

        # Callbacks

        @impl Rabbit.Broker
        def init(_type, opts) do
          # Perform any configuration
          # You can implement the callback for each component of the broker based
          # on the first arg.
          {:ok, opts}
        end

        @impl Rabbit.Broker
        def handle_message(message) do
          # Handle consumed messages
          {:ack, message}
        end

        @impl Rabbit.Broker
        def handle_error(message) do
          # Handle errors that occur within handle_message/1
          {:nack, message}
        end
      end

      # Start the broker
      MyBroker.start_link(
        connection: [uri: "amqp://guest:guest@127.0.0.1:5672"],
        topology: [
          queues: [[name: "foo"], [name: "bar"]]
        ],
        producer: [pool_size: 10],
        consumers: [[queue: "foo"], [queue: "bar", prefetch_count: 10]]
      )
  """

  alias Rabbit.Broker

  @type t :: module()
  @type option ::
          {:connection, Rabbit.Connection.options()}
          | {:topology, Rabbit.Topology.options()}
          | {:producer, Rabbit.Producer.options()}
          | {:consumers, Rabbit.ConsumerSupervisor.consumers()}
  @type options :: [option()]

  @doc """
  A callback executed by each component of the broker.

  Seven versions of the callback can be created. The callback is differentiated
  based on the first arg.

  * `:connection_pool` - Callback for the connection pool.
  * `:connection` - Callback for each connection in the pool.
  * `:topology` - Callback for the topology.
  * `:producer_pool` - Callback for the producer pool.
  * `:producer` - Callback for each producer in the pool.
  * `:consumer_supervisor` - Callback for the consumer supervisor.
  * `:consumer` - Callback for each consumer.

        # Initialize the connection pool
        def init(:connection_pool, opts) do
          {:ok, opts}
        end

        # Initialize a single connection
        def init(:connection, opts) do
          {:ok, opts}
        end

        # Initialize the topology
        def init(:topology, opts) do
          {:ok, opts}
        end

        # And so on....

  Returning `{:ok, opts}` - where `opts` is a keyword list will cause `start_link/3`
  to return `{:ok, pid}` and the broker to enter its loop.

  Returning `:ignore` will cause `start_link/3` to return `:ignore` and the process
  will exit normally without entering the loop.
  """
  @callback init(
              :connection_pool
              | :connection
              | :topology
              | :producer_pool
              | :producer
              | :consumer_supervisor
              | :consumer,
              keyword()
            ) :: {:ok, keyword()} | :ignore

  @doc """
  A callback executed by each consumer to handle message consumption.

  Please see `c:Rabbit.Consumer.handle_message/1` for more information.
  """
  @callback handle_message(message :: Rabbit.Message.t()) :: Rabbit.Consumer.message_response()

  @doc """
  A callback executed by each consumer to handle message exceptions.

  Please see `c:Rabbit.Consumer.handle_error/1` for more information.
  """
  @callback handle_error(message :: Rabbit.Message.t()) :: Rabbit.Consumer.message_response()

  ################################
  # Public API
  ################################

  @doc """
  Starts a broker process.

  ## Options

    * `:connection` - A keyword list of `t:Rabbit.Connection.option/0`.
    * `:topology` - A keyword list of `t:Rabbit.Topology.option/0`.
    * `:producer` - A keyword list of `t:Rabbit.Producer.option/0`.
    * `:consumers` - A list of `t:Rabbit.ConsumerSupervisor.consumers/0`.

  ## Server Options

  You can also provide server options - which are simply the same ones available
  for `t:GenServer.options/0`.

  """
  @spec start_link(module(), options(), GenServer.options()) :: Supervisor.on_start()
  def start_link(module, opts \\ [], server_opts \\ []) do
    Broker.Supervisor.start_link(module, opts, server_opts)
  end

  @doc """
  Publishes a message using the provided broker.

  The broker MUST be a broker module, and not a broker PID.

  Please see the `Rabbit.Producer.publish/6` documentation for further details.
  """
  @spec publish(
          Rabbit.Broker.t(),
          Rabbit.Producer.exchange(),
          Rabbit.Producer.routing_key(),
          Rabbit.Producer.message(),
          Rabbit.Producer.publish_options(),
          timeout()
        ) :: :ok | {:error, any()}
  def publish(module, exchange, routing_key, payload, opts \\ [], timeout \\ 5_000) do
    producer = producer(module)
    Rabbit.Producer.publish(producer, exchange, routing_key, payload, opts, timeout)
  end

  @doc """
  Stops a broker process.
  """
  @spec stop(Rabbit.Broker.t()) :: :ok
  def stop(broker) do
    Supervisor.stop(broker, :normal)
  end

  @doc false
  def connection(module), do: Module.concat(module, Connection)

  @doc false
  def topology(module), do: Module.concat(module, Topology)

  @doc false
  def producer(module), do: Module.concat(module, Producer)

  @doc false
  def consumers(module), do: Module.concat(module, Consumers)

  defmacro __using__(opts) do
    quote location: :keep do
      @behaviour Rabbit.Broker

      if Module.get_attribute(__MODULE__, :doc) == nil do
        @doc """
        Returns a specification to start this broker under a supervisor.
        See `Supervisor`.
        """
      end

      def child_spec(args) do
        default = %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [args]}
        }

        Supervisor.child_spec(default, unquote(Macro.escape(opts)))
      end

      defoverridable(child_spec: 1)
    end
  end
end
