defmodule Rabbit.ProducerPool do
  @moduledoc """
  A RabbitMQ producer pool process.

  This mirrors the API of the `Rabbit.Producer` module, except is creates a
  pool of producer processes. It provides all the same producer guarantees as
  `Rabbit.Producer`, as well as:

  * Channel pooling for increased publishing performance.

  ## Example

      # This is a connection
      defmodule MyConnection do
        use Rabbit.Connection

        def start_link(opts \\\\ []) do
          Rabbit.Connection.start_link(__MODULE__, opts, name: __MODULE__)
        end

        # Callbacks

        @impl Rabbit.Connection
        def init(_type, opts) do
          {:ok, opts}
        end
      end

      # This is a producer pool
      defmodule MyProducerPool do
        use Rabbit.ProducerPool

        def start_link(opts \\\\ []) do
          Rabbit.ProducerPool.start_link(__MODULE__, opts, name: __MODULE__)
        end

        # Callbacks

        @impl Rabbit.ProducerPool
        def init(:producer_pool, opts) do
          # Perform any runtime configuration for the pool
          {:ok, opts}
        end

        def init(:producer, opts) do
          # Perform any runtime configuration per producer
          {:ok, opts}
        end
      end

      # Start the connection
      MyConnection.start_link()

      # Start the producer pool
      MyProducerPool.start_link(connection: MyConnection, publish_opts: [content_type: "application/json"])

      # Publish a message
      Rabbit.ProducerPool.publish(MyProducerPool, "", "my_queue", %{foo: "bar"})

  """

  alias Rabbit.Producer

  @type t :: GenServer.name()
  @type option ::
          {:pool_size, non_neg_integer()}
          | {:max_overflow, non_neg_integer()}
          | {:strategy, :lifo | :fifo}
          | Rabbit.Producer.option()
  @type options :: [option()]

  @doc """
  A callback executed by each component of the producer pool.

  Two versions of the callback must be created. One for the pool, and one
  for the producers. The first argument differentiates the callback.

        # Initialize the pool
        def init(:producer_pool, opts) do
          {:ok, opts}
        end

        # Initialize a single producer
        def init(:producer, opts) do
          {:ok, opts}
        end

  Returning `{:ok, opts}` - where `opts` is a keyword list of `t:option()` will,
  cause `start_link/3` to return `{:ok, pid}` and the process to enter its loop.

  Returning `:ignore` will cause `start_link/3` to return `:ignore` and the process
  will exit normally without entering the loop
  """
  @callback init(:producer_pool | :producer, options()) :: {:ok, options()} | :ignore

  @doc """
  An optional callback executed after the channel is open for each producer.

  The callback is called with an `AMQP.Channel`. At the most basic, you may want
  to declare queues that you will be publishing to.

      def handle_setup(channel) do
        AMQP.Queue.declare(channel, "some_queue")

        :ok
      end

  The callback must return an `:ok` atom - otherise it will be marked as failed,
  and the producer will attempt to go through the connection setup process again.

  Alternatively, you could use a `Rabbit.Initializer` process to perform this
  setup work. Please see its docs for more information.
  """
  @callback handle_setup(channel :: AMQP.Channel.t()) :: :ok | :error

  @optional_callbacks handle_setup: 1

  ################################
  # Public API
  ################################

  @doc """
  Starts a producer pool process.

  ## Options

    * `:pool_size` - The number of processes to create for producers - defaults to `1`.
      Each process consumes a RabbitMQ channel.
    * `:max_overflow` - Maximum number of temporary workers created when the pool
      is empty - defaults to `0`.
    * `:stratgey` - Determines whether checked in workers should be placed first
      or last in the line of available workers - defaults to `:lifo`.

  ## Producer Options

  You can also provide producer options - which are simply the same ones
  available for `t:Rabbit.Producer.options/0`.

  ## Server Options

  You can also provide server options - which are simply the same ones available
  for `t:GenServer.options/0`.

  """
  @spec start_link(module(), options(), GenServer.options()) :: GenServer.on_start()
  def start_link(module, opts \\ [], server_opts \\ []) do
    Producer.Pool.start_link(module, opts, server_opts)
  end

  @doc """
  Stops the producer pool.
  """
  @spec stop(Rabbit.ProducerPool.t()) :: :ok
  def stop(producer_pool) do
    for {_, worker, _, _} <- GenServer.call(producer_pool, :get_all_workers) do
      :ok = GenServer.call(worker, :disconnect)
    end

    :poolboy.stop(producer_pool)
  end

  @doc """
  Runs the given function inside a transaction.

  The function must accept a connection pid.
  """
  @spec transaction(Rabbit.ProducerPool.t(), (Rabbit.Prodcuer.t() -> any())) :: any()
  def transaction(producer_pool, fun) do
    :poolboy.transaction(producer_pool, &fun.(&1))
  end

  @doc """
  Publishes a message using the provided producer pool.

  Please see `Rabbit.Producer.publish/6` for more information.

  """
  @spec publish(
          Rabbit.ProducerPool.t(),
          Rabbit.Producer.exchange(),
          Rabbit.Producer.routing_key(),
          Rabbit.Producer.message(),
          Rabbit.Producer.publish_options(),
          timeout()
        ) :: :ok | {:error, any()}
  def publish(producer_pool, exchange, routing_key, payload, opts \\ [], timeout \\ 5_000) do
    :poolboy.transaction(
      producer_pool,
      &Producer.publish(&1, exchange, routing_key, payload, opts, timeout)
    )
  end

  defmacro __using__(opts) do
    quote location: :keep do
      @behaviour Rabbit.ProducerPool

      if Module.get_attribute(__MODULE__, :doc) == nil do
        @doc """
        Returns a specification to start this connection pool under a supervisor.
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
