defmodule Rabbit.Consumer do
  @moduledoc """
  A RabbitMQ consumer process.

  This wraps around the standard `AMQP.Channel`. It provides the following benefits:

  * Durability during connection and channel failures through use of expotential backoff.
  * Channel pooling for increased publishing performance.
  * Ability to create module-based consumers that permit easy runtime setup
    through the `c:init/1` and `c:after_connect/2` callbacks.
  * Automatic acknowledgements based on the return value of the `c:handle_message/1` callback.
  * Ability to handle exception responses through the `c:handle_error/1` callback.
  * Each message is executed within its own supervised task.

  ## Example

      defmodule MyConnection do
        use Rabbit.Connection
      end

      defmodule MyConsumer do
        use Rabbit.Consumer

        def init(opts) do
          # Perform any runtime configuration...
          {:ok, opts}
        end

        def after_connect(channel, queue) do
          # Perform any runtime exchange or queue setup...
          AMQP.Queue.declare(channel, queue)

          :ok
        end

        def handle_message(message) do
          {:ack, message}
        end

        def handle_error(message) do
          {:nack, message}
        end
      end

      MyConnection.start_link()
      MyConsumer.start_link(MyConnection, queue: "my_queue", prefetch_count: 20)

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
  @type action :: :ack | :nack | :reject
  @type action_options :: [{:multiple, boolean()} | {:requeue, boolean()}]
  @type result ::
          {action(), Rabbit.Message.t()} | {action(), Rabbit.Message.t(), action_options()}

  @doc """
  Starts a RabbitMQ consumer process.

  ## Options
    * `:uri` - The connection URI. This takes priority over other connection  attributes.

  """
  @callback start_link(Rabbit.Connection.t(), options()) :: GenServer.on_start()

  @doc """
  Stops a RabbitMQ consumer process.
  """
  @callback stop() :: :ok

  @callback init(options()) :: {:ok, options()} | :ignore

  @callback after_connect(AMQP.Channel.t(), queue :: String.t()) :: :ok

  @callback handle_message(Rabbit.Message.t()) :: result() | any()

  @callback handle_error(Rabbit.Message.t()) :: result() | any()

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
