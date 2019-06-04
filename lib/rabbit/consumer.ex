defmodule Rabbit.Consumer do
  @moduledoc """
  A RabbitMQ consumer process.

  This wraps around the standard `AMQP.Channel`. It provides the following benefits:

  * Durability during connection and channel failures through use of expotential backoff.
  * Ability to create module-based consumers that permit easy runtime setup
    through the `c:init/1` and `c:after_connect/2` callbacks.
  * Automatic acknowledgements based on the return value of the `c:handle_message/1` callback.
  * Ability to handle exceptions through the `c:handle_error/1` callback.
  * Each message is executed within its own supervised task.
  * Automatic payload decoding based on available serializers and message
    content type.

  ## Example

      # This is a connection
      defmodule MyConnection do
        use Rabbit.Connection
      end

      # This is a consumer
      defmodule MyConsumer do
        use Rabbit.Consumer

        # Callbacks

        # Perform any runtime configuration
        def init(opts) do
          {:ok, opts}
        end

        # Perform exchange or queue setup
        def after_connect(channel, queue) do
          AMQP.Queue.declare(channel, queue)

          :ok
        end

        # Handle consumed messages
        def handle_message(message) do
          {:ack, message}
        end

        # Handle errors that occur within handle_message/1
        def handle_error(message) do
          {:nack, message}
        end
      end

      # Start the connection
      MyConnection.start_link()

      # Start the consumer
      MyConsumer.start_link(MyConnection, queue: "my_queue", prefetch_count: 20)

  ## Serializers

  When a message is consumed, its content type is compared to the list of available
  serializers. If a serializer matches the content type, the message will be
  automatically decoded.

  You can find out more about serializers at `Rabbit.Serializer`.
  """

  alias Rabbit.Consumer

  @type t :: GenServer.name()
  @type option ::
          {:queue, String.t()}
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
  Starts a RabbitMQ consumer process.

  ## Options
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

  """
  @callback start_link(connection :: Rabbit.Connection.t(), options()) :: GenServer.on_start()

  @doc """
  Stops a RabbitMQ consumer process.
  """
  @callback stop() :: :ok

  @doc """
  A callback executed when the consumer starts.

  The options passed represent the options that will be used by the consumer.
  This must return `{:ok, keyword}` or `:ignore`.
  """
  @callback init(options()) :: {:ok, options()} | :ignore

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
  @callback after_connect(channel :: AMQP.Channel.t(), queue :: String.t()) :: :ok

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

  @optional_callbacks init: 1, after_connect: 2

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
  @spec start_link(Rabbit.Connection.t(), options(), GenServer.options()) :: Supervisor.on_start()
  def start_link(connection, opts \\ [], server_opts \\ []) do
    Consumer.Server.start_link(connection, opts, server_opts)
  end

  @doc false
  def stop(consumer) do
    GenServer.stop(consumer, :normal)
  end

  @doc false
  def ack(consumer, delivery_tag, opts \\ []) do
    GenServer.cast(consumer, {:ack, delivery_tag, opts})
  end

  @doc false
  def nack(consumer, delivery_tag, opts \\ []) do
    GenServer.cast(consumer, {:nack, delivery_tag, opts})
  end

  @doc false
  def reject(consumer, delivery_tag, opts \\ []) do
    GenServer.cast(consumer, {:reject, delivery_tag, opts})
  end

  defmacro __using__(_) do
    quote do
      @behaviour Rabbit.Consumer

      def child_spec(args) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, args}
        }
      end

      @impl Rabbit.Consumer
      def start_link(connection, opts \\ [], server_opts \\ []) do
        opts = Keyword.put(opts, :module, __MODULE__)
        server_opts = Keyword.put(server_opts, :name, __MODULE__)

        Consumer.start_link(connection, opts, server_opts)
      end

      @impl Rabbit.Consumer
      def stop do
        Consumer.stop(__MODULE__)
      end
    end
  end
end
