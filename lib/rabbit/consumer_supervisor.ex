defmodule Rabbit.ConsumerSupervisor do
  @moduledoc """
  A RabbitMQ consumer supervisor process.

  This enables starting and supervising multiple `Rabbit.Consumer` processes with ease.

  ## Example

      # This is a connection
      defmodule MyConnection do
        use Rabbit.Connection
      end

      # This is a consumer supervisor
      defmodule MyConsumers do
        use Rabbit.ConsumerSupervisor

        # Callbacks

        # Setup the consumers you want
        def consumers do
          [
            [queue: "myqueue1", prefetch_count: 10],
            [queue: "myqueue2", prefetch_count: 10]
          ]
        end

        # Perform any runtime configuration per consumer
        def init(opts) do
          {:ok, opts}
        end

        # Perform exchange or queue setup per consumer
        def after_connect(channel, queue) do
          AMQP.Queue.declare(channel, queue)

          :ok
        end

        # Handle messages per consumer
        def handle_message(message) do
          {:ack, message}
        end

        # Handle errors that occur per consumer
        def handle_error(message) do
          {:nack, message}
        end
      end

      # Start the connection
      MyConnection.start_link()

      # Start the consumers
      MyConsumers.start_link(MyConnection)

  Please see the documentation for `Rabbit.Consumer` for more details.

  """
  alias Rabbit.{Consumer, ConsumerSupervisor}

  @type t :: Supervisor.name()
  @type consumers() :: [Rabbit.Consumer.options()]

  @doc """
  Starts a consumer supervisor process.
  """
  @callback start_link(connection :: Rabbit.Connection.t(), server_opts :: GenServer.options()) ::
              Supervisor.on_start()

  @doc """
  Stops a consumer supervisor process.
  """
  @callback stop() :: :ok

  @doc """
  A callback used to fetch the list of consumers under the supervisor.

  This callback must return a list of `t:Rabbit.Consumer.options/0`
  """
  @callback consumers() :: consumers()

  @doc """
  Please see `c:Rabbit.Consumer.init/1` for details.
  """
  @callback init(options :: Rabbit.Consumer.options()) ::
              {:ok, Rabbit.Consumer.options()} | :ignore

  @doc """
  Please see `c:Rabbit.Consumer.after_connect/2` for details.
  """
  @callback after_connect(channel :: AMQP.Channel.t(), queue :: String.t()) :: :ok

  @doc """
  Please see `c:Rabbit.Consumer.handle_message/1` for details.
  """
  @callback handle_message(message :: Rabbit.Message.t()) ::
              {:ack, Rabbit.Message.t()}
              | {:ack, Rabbit.Message.t(), Keyword.t()}
              | {:nack, Rabbit.Message.t()}
              | {:nack, Rabbit.Message.t(), Rabbit.Consumer.action_options()}
              | {:reject, Rabbit.Message.t()}
              | {:reject, Rabbit.Message.t(), Rabbit.Consumer.action_options()}
              | any()

  @doc """
  Please see `c:Rabbit.Consumer.handle_error/1` for details.
  """
  @callback handle_error(message :: Rabbit.Message.t()) ::
              {:ack, Rabbit.Message.t()}
              | {:ack, Rabbit.Message.t(), Rabbit.Consumer.action_options()}
              | {:nack, Rabbit.Message.t()}
              | {:nack, Rabbit.Message.t(), Rabbit.Consumer.action_options()}
              | {:reject, Rabbit.Message.t()}
              | {:reject, Rabbit.Message.t(), Rabbit.Consumer.action_options()}
              | any()

  @optional_callbacks init: 1, after_connect: 2

  ################################
  # Public API
  ################################

  @doc false
  def start_link(connection, module, server_opts \\ []) do
    Consumer.Supervisor.start_link(connection, module, server_opts)
  end

  @doc false
  def stop(consumer_supervisor) do
    Supervisor.stop(consumer_supervisor)
  end

  defmacro __using__(_) do
    quote do
      @behaviour Rabbit.ConsumerSupervisor

      def child_spec(args) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, args}
        }
      end

      @impl Rabbit.ConsumerSupervisor
      def start_link(connection, server_opts \\ []) do
        server_opts = Keyword.put(server_opts, :name, __MODULE__)
        ConsumerSupervisor.start_link(connection, __MODULE__, server_opts)
      end

      @impl Rabbit.ConsumerSupervisor
      def stop do
        ConsumerSupervisor.stop(__MODULE__)
      end
    end
  end
end
