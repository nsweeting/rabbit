defmodule Rabbit.Consumer do
  @moduledoc """
  A RabbitMQ consumer process.

  Consumers are the "workers" of your application. They wrap around the standard
  `AMQP.Channel` and provide the following benefits:

  * Durability during connection and channel failures through use of exponential backoff.
  * Easy runtime setup through the `c:init/2` and `c:handle_setup/1` callbacks.
  * Automatic acknowledgements based on the return value of the `c:handle_message/1` callback.
  * Ability to handle exceptions through the `c:handle_error/1` callback.
  * Each message is executed within its own supervised task.
  * Automatic payload decoding based on available serializers and message
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
        def init(:connection, opts) do
          # Perform any runtime configuration
          {:ok, opts}
        end
      end

      # This is a consumer
      defmodule MyConsumer do
        use Rabbit.Consumer

        def start_link(opts \\\\ []) do
          Rabbit.Consumer.start_link(__MODULE__, opts, name: __MODULE__)
        end

        # Callbacks

        @impl Rabbit.Consumer
        def init(_type, opts) do
          # Perform any runtime configuration
          {:ok, opts}
        end

        @impl Rabbit.Consumer
        def handle_setup(state) do
          # Optional callback to perform exchange or queue setup
          AMQP.Queue.declare(state.channel, state.queue)

          :ok
        end

        @impl Rabbit.Consumer
        def handle_message(message) do
          # Handle consumed messages
          {:ack, message}
        end

        @impl Rabbit.Consumer
        def handle_error(message) do
          # Handle errors that occur within handle_message/1
          {:nack, message}
        end
      end

      # Start the connection
      MyConnection.start_link()

      # Start the consumer
      MyConsumer.start_link(connection: MyConnection, queue: "my_queue", prefetch_count: 20)

  ## Serializers

  When a message is consumed, its content type is compared to the list of available
  serializers. If a serializer matches the content type, the message will be
  automatically decoded.

  You can find out more about serializers at `Rabbit.Serializer`.
  """

  alias Rabbit.Consumer

  @type t :: GenServer.name()
  @type option ::
          {:connection, Rabbit.Connection.t()}
          | {:queue, String.t()}
          | {:prefetch_count, non_neg_integer()}
          | {:prefetch_size, non_neg_integer()}
          | {:consumer_tag, String.t()}
          | {:no_local, boolean()}
          | {:no_ack, boolean()}
          | {:exclusive, boolean()}
          | {:nowait, boolean()}
          | {:arguments, Keyword.t()}
          | {:custom_meta, map()}
          | {:setup_opts, setup_options()}
          | {:sync_start, boolean()}
          | {:sync_start_delay, non_neg_integer()}
          | {:sync_start_max, non_neg_integer()}
  @type options :: [option()]
  @type delivery_tag :: non_neg_integer()
  @type action_options :: [{:multiple, boolean()} | {:requeue, boolean()}]
  @type message_response ::
          {:ack, Rabbit.Message.t()}
          | {:ack, Rabbit.Message.t(), action_options()}
          | {:nack, Rabbit.Message.t()}
          | {:nack, Rabbit.Message.t(), action_options()}
          | {:reject, Rabbit.Message.t()}
          | {:reject, Rabbit.Message.t(), action_options()}
          | any()
  @type setup_options :: keyword()

  @doc """
  A callback executed when the consumer is started.

  Returning `{:ok, opts}` - where `opts` is a keyword list of `t:option()` will,
  cause `start_link/3` to return `{:ok, pid}` and the process to enter its loop.

  Returning `:ignore` will cause `start_link/3` to return `:ignore` and the process
  will exit normally without entering the loop.
  """
  @callback init(:consumer, options()) :: {:ok, options()} | :ignore

  @doc """
  An optional callback executed after the channel is open, but before consumption.

  The callback is called with the current state, containing the open channel and queue name if
  given. At the most basic, you may want to declare the queue to ensure it's available. This will
  be entirely application dependent though.

      def handle_setup(state) do
        AMQP.Queue.declare(state.channel, state.queue)

        :ok
      end

  Important keys from the state include:

  * `:connection` - the `Rabbit.Connection` module in use.
  * `:channel` - the `AMQP.Channel` open for this consumer.
  * `:queue` - the queue name.
  * `:setup_opts` - as provided to `start_link/3`.

  Return either `:ok` or `{:ok, new_state}` for success, the latter will update the state.

  If another value is returned it will be marked as failed, and the consumer will attempt to go
  through the connection setup process again.

  Alternatively, you could use a `Rabbit.Topology` process to perform this
  setup work. Please see its docs for more information.
  """
  @callback handle_setup(state :: map) :: :ok | {:ok, new_state :: map()} | :error

  @doc """
  A callback executed to handle message consumption.

  The callback is provided a `Rabbit.Message` struct. You may find more information
  about the message structure within its own documentation. The message may be
  automatically decoded based on the content type and available serializers.

  You may choose to ack, nack, or reject the message based on the return value.

  * `{:ack, message}` - will acknowledge the message.
  * `{:ack, message, options}` - will acknowledge the message with options.
  * `{:nack, message}` - will negative acknowledge the message.
  * `{:nack, message, options}` - will negative acknowledge the message with options.
  * `{:reject, message}` - will reject the message.
  * `{:reject, message, options}` - will reject the message with options.

  If you don't return one of these values - nothing will be done. This means you
  will need to manually ack, nack or reject the message if required. Please
  see the `Rabbit.Message` module for more information.
  """
  @callback handle_message(message :: Rabbit.Message.t()) :: message_response()

  @doc """
  A callback executed to handle message exceptions.

  If the original `c:handle_message/1` callback raises an error, this callback
  will be called with the message - but with the `:error_reason` and `:error_stack`
  fields filled.

  You may choose to return the same values as `c:handle_message/1`.
  """
  @callback handle_error(message :: Rabbit.Message.t()) :: message_response()

  @optional_callbacks handle_setup: 1

  ################################
  # Public API
  ################################

  @doc """
  Starts a consumer process.

  ## Options

    * `:connection` - A `Rabbit.Connection` process.
    * `:queue` - The queue to consume messages from.
    * `:prefetch_count` - The basic unit of concurrency for a given consumer - defaults to `0`.
    * `:prefetch_size` - The prefetch window size in octets - defaults to `0`, meaning
      no specific limit.
    * `:consumer_tag` - The identifier of the consumer. If empty, one will be
      generated by the server.
    * `:no_local` - A boolean representing whether messages should not be sent to the
      same connection that published them - defaults to `false`.
    * `:no_ack` - A boolean representing whether acknowledgements are not required for
      messages - defaults to `false`.
    * `:exclusive` - A boolean representing whether only this consumer can access
      the queue - defaults to `false`.
    * `:nowait` - A boolean representing whether the server should not respond to
      methods - defaults to `false`.
    * `:arguments` - A set of arguments for the consumer.
    * `:custom_meta` - A map of custom data that will be included in each `Rabbit.Message`
      handled by the consumer.
    * `:setup_opts` - A keyword list of custom options for use in `c:handle_setup/1`.
    * `:sync_start` - Boolean representing whether to establish the connection,
      channel, and setup synchronously - defaults to `false`.
    * `:sync_start_delay` - The amount of time in milliseconds to sleep between
      sync start attempts - defaults to `50`.
    * `:sync_start_max` - The max amount of sync start attempts that will occur
      before proceeding with async start - defaults to `100`.

  ## Server Options

  You can also provide server options - which are simply the same ones available
  for `t:GenServer.options/0`.

  """
  @spec start_link(module(), options(), GenServer.options()) :: Supervisor.on_start()
  def start_link(module, opts \\ [], server_opts \\ []) do
    Consumer.Server.start_link(module, opts, server_opts)
  end

  @doc """
  Stops a consumer process.
  """
  @spec stop(Rabbit.Consumer.t()) :: :ok
  def stop(consumer) do
    GenServer.stop(consumer, :normal)
  end

  defmacro __using__(opts) do
    quote location: :keep do
      @behaviour Rabbit.Consumer

      if Module.get_attribute(__MODULE__, :doc) == nil do
        @doc """
        Returns a specification to start this consumer under a supervisor.
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
