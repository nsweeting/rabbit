defmodule Rabbit.Producer do
  @moduledoc """
  A RabbitMQ producer process.

  Producers are needed to publish any messages to RabbitMQ. They wrap around the
  standard `AMQP.Channel` and provide the following benefits:

  * Durability during connection and channel failures through use of expotential backoff.
  * Channel pooling for increased publishing performance.
  * Easy runtime setup through an `c:init/2` and `c:handle_setup/1` or `c:handle_setup/2` callbacks.
  * Simplification of standard publishing options.
  * Automatic payload encoding based on available serializers and message
    content type.

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

      # This is a producer
      defmodule MyProducer do
        use Rabbit.Producer

        def start_link(opts \\\\ []) do
          Rabbit.Producer.start_link(__MODULE__, opts, name: __MODULE__)
        end

        # Callbacks

        @impl Rabbit.Producer
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

      # Start the producer
      MyProducer.start_link(connection: MyConnection, publish_opts: [content_type: "application/json"])

      # Publish a message
      Rabbit.Producer.publish(MyProducer, "", "my_queue", %{foo: "bar"})

  ## Serializers

  When a message is published, its content type is compared to the list of available
  serializers. If a serializer matches the content type, the message will be
  automatically encoded.

  You can find out more about serializers at `Rabbit.Serializer`.
  """

  alias Rabbit.Producer

  @type t :: GenServer.name()
  @type option ::
          {:connection, Rabbit.Connection.t()}
          | {:pool_size, non_neg_integer()}
          | {:max_overflow, non_neg_integer()}
          | {:strategy, :lifo | :fifo}
          | {:sync_start, boolean()}
          | {:sync_start_delay, non_neg_integer()}
          | {:sync_start_max, non_neg_integer()}
          | {:publish_opts, publish_options()}
          | {:setup_opts, setup_options()}
  @type options :: [option()]
  @type exchange :: String.t()
  @type routing_key :: String.t()
  @type message :: term()
  @type publish_option ::
          {:mandatory, boolean()}
          | {:immediate, boolean()}
          | {:content_type, String.t()}
          | {:content_encoding, String.t()}
          | {:headers, [{String.t(), String.t()}]}
          | {:persistent, boolean()}
          | {:correlation_id, String.t()}
          | {:priority, 1..9}
          | {:reply_to, String.t()}
          | {:expiration, non_neg_integer()}
          | {:message_id, String.t()}
          | {:timestamp, non_neg_integer()}
          | {:type, String.t()}
          | {:user_id, String.t()}
          | {:app_id, String.t()}
  @type publish_options :: [publish_option()]
  @type setup_options :: keyword()

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
  and the producer will attempt to go through the channel setup process again.

  Alternatively, you could use a `Rabbit.Topology` process to perform this
  setup work. Please see its docs for more information.
  """
  @callback handle_setup(channel :: AMQP.Channel.t()) :: :ok | :error

  @doc """
  The same as `handle_setup/1` but includes the current state as a second argument.

  Important keys in the state include:

  * `:connection` - the `Rabbit.Connection` process.
  * `:channel` - the opened `AMQP.Channel` channel.
  * `:setup_opts` - options provided undert the key `:setup_opts` to `start_link/3`.
  """
  @callback handle_setup(channel :: AMQP.Channel.t(), state :: map()) :: :ok | :error

  @optional_callbacks handle_setup: 1, handle_setup: 2

  ################################
  # Public API
  ################################

  @doc """
  Starts a producer process.

  ## Options

    * `:connection` - A `Rabbit.Connection` process.
    * `:pool_size` - The number of processes to create for producers - defaults to `1`.
      Each process consumes a RabbitMQ channel.
    * `:max_overflow` - Maximum number of temporary workers created when the pool
      is empty - defaults to `0`.
    * `:stratgey` - Determines whether checked in workers should be placed first
      or last in the line of available workers - defaults to `:lifo`.
    * `:sync_start` - Boolean representing whether to establish the connection
      and channel syncronously - defaults to `true`.
    * `:sync_start_delay` - The amount of time in milliseconds to sleep between
      sync start attempts - defaults to `50`.
    * `:sync_start_max` - The max amount of sync start attempts that will occur
      before proceeding with async start - defaults to `100`.
    * `:publish_opts` - Any `t:publish_option/0` that is automatically set as a
      default option value when calling `publish/6`.
    * `:setup_opts` - a keyword list of values to provide to `c:handle_setup/2`.

  ## Server Options

  You can also provide server options - which are simply the same ones available
  for `t:GenServer.options/0`.

  """
  @spec start_link(module(), options(), GenServer.options()) ::
          Supervisor.on_start()
  def start_link(module, opts \\ [], server_opts \\ []) do
    Producer.Pool.start_link(module, opts, server_opts)
  end

  @doc """
  Runs the given function inside a transaction.

  The function must accept a producer child pid.
  """
  @spec transaction(Rabbit.Producer.t(), (Rabbit.Producer.t() -> any())) :: any()
  def transaction(producer, fun) do
    :poolboy.transaction(producer, &fun.(&1))
  end

  @doc """
  Stops a producer process.
  """
  @spec stop(Rabbit.Producer.t()) :: :ok
  def stop(producer) do
    for {_, worker, _, _} <- GenServer.call(producer, :get_all_workers) do
      :ok = GenServer.call(worker, :disconnect)
    end

    :poolboy.stop(producer)
  end

  @doc """
  Publishes a message using the provided producer.

  All publishing options can be provided to the producer during process start.
  They would then be used as defaults during publishing. Options provided to this
  function would overwrite any defaults the producer has.

  ## Serializers

  If a `content_type` is provided as an option - and it matches one of the available
  serializers, the payload will be automatically encoded using that serializer.

  For example, we could automatically encode our payload to json if we do the
  following:

        Rabbit.Producer.publish(MyProducer, "", "my_queue", %{foo: "bar"}, content_type: "application/json")

  Please see the documention at `Rabbit.Serializer` for more information.

  ## Options

    * `:mandatory` - If set, returns an error if the broker can't route the message
      to a queue - defaults to `false`.
    * `:immediate` - If set, returns an error if the broker can't deliver te message
      to a consumer immediately - defaults to `false`.
    * `:content_type` - MIME Content type.
    * `:content_encoding` - MIME Content encoding.
    * `:headers` - Message headers. Can be used with headers Exchanges.
    * `:persistent` - If set, uses persistent delivery mode. Messages marked as
      persistent that are delivered to durable queues will be logged to disk.
    * `:correlation_id` - Application correlation identifier
    * `:priority` - Message priority, ranging from 0 to 9.
    * `:reply_to` - Name of the reply queue.
    * `:expiration` - How long the message is valid (in milliseconds).
    * `:message_id` - Message identifier.
    * `:timestamp` - Timestamp associated with this message (epoch time).
    * `:type` - Message type as a string.
    * `:user_id` - Creating user ID. RabbitMQ will validate this against the active
      connection user.
    * `:app_id` - Publishing application ID.

  """
  @spec publish(
          Rabbit.Producer.t(),
          exchange(),
          routing_key(),
          message(),
          publish_options(),
          timeout()
        ) :: :ok | {:error, any()}
  def publish(producer, exchange, routing_key, payload, opts \\ [], timeout \\ 5_000) do
    message = {exchange, routing_key, payload, opts}
    :poolboy.transaction(producer, &GenServer.call(&1, {:publish, message}, timeout))
  end

  defmacro __using__(opts) do
    quote location: :keep do
      @behaviour Rabbit.Producer

      if Module.get_attribute(__MODULE__, :doc) == nil do
        @doc """
        Returns a specification to start this producer under a supervisor.
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
