defmodule Rabbit.ConsumerSupervisor do
  @moduledoc """
  A RabbitMQ consumer supervisor process.

  This allows starting and supervising multiple `Rabbit.Consumer` processes with
  ease. Rather than creating a module for each consumer and implementing repetitive
  logic - the same callbacks are used across all child consumers.

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

      # This is a consumer supervisor
      defmodule MyConsumers do
        use Rabbit.ConsumerSupervisor

        def start_link(consumers \\\\ []) do
          Rabbit.ConsumerSupervisor.start_link(__MODULE__, consumers, name: __MODULE__)
        end

        # Callbacks

        @impl Rabbit.ConsumerSupervisor
        def init(:consumer_supervisor, _consumers) do
          # Perform any runtime configuration for the supervisor
          consumers = [
            [connection: MyConnection, queue: "my_queue1", prefetch_count: 5],
            [connection: MyConnection, queue: "my_queue2", prefetch_count: 10]
          ]

          {:ok, consumers}
        end

        def init(:consumer, opts) do
          # Perform any runtime configuration per consumer
          {:ok, opts}
        end

        @impl Rabbit.ConsumerSupervisor
        def handle_setup(channel, queue) do
          # Perform exchange or queue setup per consumer
          AMQP.Queue.declare(channel, queue)

          :ok
        end

        @impl Rabbit.ConsumerSupervisor
        def handle_message(message) do
          # Handle messages per consumer
          {:ack, message}
        end

        @impl Rabbit.ConsumerSupervisor
        def handle_error(message) do
          # Handle errors that occur per consumer
          {:nack, message}
        end
      end

      # Start the connection
      MyConnection.start_link()

      # Start the consumers
      MyConsumers.start_link()

  """
  alias Rabbit.Consumer

  @type t :: Supervisor.name()
  @type consumers() :: [Rabbit.Consumer.options()]

  @doc """
  A callback executed by each component of the consumer supervisor.

  Two versions of the callback must be created. One for the supervisor, and one
  for the consumers. The first argument differentiates the callback.

        # Initialize the supervisor
        def init(:consumer_supervisor, consumers) do
          {:ok, consumers}
        end

        # Initialize a single consumer
        def init(:consumer, opts) do
          {:ok, opts}
        end

  Returning `{:ok, consumers}` - where `consumers` is a list of `t:Rabbit.Consumer.options/0`
  will, cause `start_link/3` to return `{:ok, pid}` and the supervisor to enter its loop.

  Returning `{:ok, opts}` - where `opts` is a keyword list of `t:Rabbit.Consumer.option/0` will,
  cause `start_link/3` to return `{:ok, pid}` and the consumer to enter its loop.

  Returning `:ignore` will cause `start_link/3` to return `:ignore` and the process
  will exit normally without entering the loop.
  """
  @callback init(
              type :: :consumer_supervisor | :consumer,
              opts :: consumers() | Rabbit.Consumer.options()
            ) ::
              {:ok, consumers() | Rabbit.Consumer.options()} | :ignore

  @doc """
  A callback executed by each consumer after the channel is open, but before
  consumption.

  Please see `c:Rabbit.Consumer.handle_setup/1` for more information.
  """
  @callback handle_setup(state :: map()) :: :ok | {:ok, new_state :: map()} | :error

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

  @optional_callbacks handle_setup: 1

  ################################
  # Public API
  ################################

  @doc """
  Starts a consumer supervisor process.

  The list of consumers should represent a list of `t:Rabbit.Consumer.options/0`.

  ## Server Options

  You can also provide server options - which are simply the same ones available
  for `t:GenServer.options/0`.

  """
  def start_link(module, consumers \\ [], server_opts \\ []) do
    Consumer.Supervisor.start_link(module, consumers, server_opts)
  end

  @doc false
  def stop(consumer_supervisor) do
    Supervisor.stop(consumer_supervisor)
  end

  defmacro __using__(opts) do
    quote location: :keep do
      @behaviour Rabbit.ConsumerSupervisor

      if Module.get_attribute(__MODULE__, :doc) == nil do
        @doc """
        Returns a specification to start this consumer supervisor under a supervisor.
        See `Supervisor`.
        """
      end

      def child_spec(args) do
        default = %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [args]},
          type: :supervisor
        }

        Supervisor.child_spec(default, unquote(Macro.escape(opts)))
      end

      defoverridable(child_spec: 1)
    end
  end
end
