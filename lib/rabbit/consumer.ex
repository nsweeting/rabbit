defmodule Rabbit.Consumer do
  @moduledoc """
  A RabbitMQ consumer process.

  This wraps around the standard `AMQP.Channel`. It provides the following benefits:

  * Durability during connection and channel failures through use of expotential backoff.
  * Easy runtime setup through the `c:init/2` and `c:handle_setup/2` callbacks.
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
        def handle_setup(channel, queue) do
          # Perform exchange or queue setup
          AMQP.Queue.declare(channel, queue)

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
          | {:no_wait, boolean()}
          | {:arguments, Keyword.t()}
  @type options :: [option()]
  @type delivery_tag :: non_neg_integer()
  @type action_options :: [{:multiple, boolean()} | {:requeue, boolean()}]

  @doc """
  A callback executed when the consumer is started.

  Returning `{:ok, opts}` - where `opts` is a keyword list of `t:option()` will,
  cause `start_link/3` to return `{:ok, pid}` and the process to enter its loop.

  Returning `:ignore` will cause `start_link/3` to return `:ignore` and the process
  will exit normally without entering the loop
  """
  @callback init(:consumer, options()) :: {:ok, options()} | :ignore

  @doc """
  A callback executed after the channel is open, but before consumption.

  The callback is called with an `AMQP.Channel`, as well as the queue that will
  be consumed. At the most basic, you will most likely want to declare the queue
  to ensure its available. This will be entirely application dependent though.

      def after_connect(channel, queue) do
        AMQP.Queue.declare(channel, queue)

        :ok
      end

  The callback must return an `:ok` atom - otherise it will be marked as failed,
  and the consumer will attempt to go through the connection setup process again.
  """
  @callback handle_setup(channel :: AMQP.Channel.t(), queue :: String.t()) :: :ok

  @doc """
  A callback executed to handle message consumption.

  The callback is called with a `Rabbit.Message` struct. You may find more information
  about the message structure within its own documentation. The message may be
  automatically decoded based on the content type and available serializers.

  You may choose to ack, nack, or reject the message based on the return value.

  * `{:ack, message}` - will awknowledge the message.
  * `{:ack, message, options}` - will awknowledge the message with options.
  * `{:nack, message}` - will negative awknowledge the message.
  * `{:nack, message, options}` - will negative awknowledge the message with options.
  * `{:reject, message}` - will reject the message.
  * `{:reject, message, options}` - will reject the message with options.

  If you dont return one of these values - nothing will be done.
  """
  @callback handle_message(message :: Rabbit.Message.t()) ::
              {:ack, Rabbit.Message.t()}
              | {:ack, Rabbit.Message.t(), action_options()}
              | {:nack, Rabbit.Message.t()}
              | {:nack, Rabbit.Message.t(), action_options()}
              | {:reject, Rabbit.Message.t()}
              | {:reject, Rabbit.Message.t(), action_options()}
              | any()

  @doc """
  A callback executed to handle message exceptions.

  If the original `c:handle_message/1` callback raises an error, this callback
  will be called with the message - but with the `:error_reason` and `:error_stack`
  fields filled.

  You may choose to return the same values as `c:handle_message/1`.
  """
  @callback handle_error(message :: Rabbit.Message.t()) ::
              {:ack, Rabbit.Message.t()}
              | {:ack, Rabbit.Message.t(), action_options()}
              | {:nack, Rabbit.Message.t()}
              | {:nack, Rabbit.Message.t(), action_options()}
              | {:reject, Rabbit.Message.t()}
              | {:reject, Rabbit.Message.t(), action_options()}
              | any()

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
      generared by the server.
    * `:no_local` - A boolean representing whether messages should not be sent to the
      same connection that published them - defaults to `false`.
    * `:no_ack` - A boolean representing whether acknowledgements are not required for
      messages - defaults to `false`.
    * `:exclusive` - A boolean representing whether only this consumer can access
      the queue - defaults to `false`.
    * `:no_wait` - A boolean representing whether the server should not respond to
      methods - defaults to `false`.
    * `:arguments` - A set of arguments for the consume.

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
  def stop(consumer) do
    GenServer.stop(consumer, :normal)
  end

  @doc """
  Awknowledges a message from its delivery tag.

  ## Options

    * `:multiple` -  If  `true`, all messages up to the one specified by `delivery_tag`
      are considered acknowledged by the server.

  """
  def ack(consumer, delivery_tag, opts \\ []) do
    GenServer.cast(consumer, {:ack, delivery_tag, opts})
  end

  @doc """
  Negative awknowledges a message from its delivery tag.

  ## Options

    * `:multiple` -  If `true`, all messages up to the one specified by `delivery_tag`
      are considered acknowledged by the server.
    * `:requeue` - If `true`, the message will be returned to the queue and redelivered
      to the next available consumer.

  """
  def nack(consumer, delivery_tag, opts \\ []) do
    GenServer.cast(consumer, {:nack, delivery_tag, opts})
  end

  @doc """
  Rejects a message from its delivery tag.

  ## Options

    * `:requeue` - If `true`, the message will be returned to the queue and redelivered
      to the next available consumer.
  """
  def reject(consumer, delivery_tag, opts \\ []) do
    GenServer.cast(consumer, {:reject, delivery_tag, opts})
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
