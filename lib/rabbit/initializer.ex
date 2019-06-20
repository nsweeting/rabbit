defmodule Rabbit.Initializer do
  @moduledoc """
  A RabbitMQ initializer process.

  This is a blocking process that can be used to declare exchanges, queues, and bindings.
  It will perform any setup required by your application. It should be added to
  your supervision tree before any producers or consumers.

  Both `Rabbit.Consumer` and `Rabbit.ConsumerSupervisor` have the `handle_setup/2`
  callback, which can be used to perform any queue, exchange or binding work as well.
  But if you have more complex requirements, this module can be used.

  ## Example

      # This is a connection
      defmodule MyConnection do
        use Rabbit.Connection

        def start_link(opts \\ []) do
          Rabbit.Connection.start_link(__MODULE__, opts, name: __MODULE__)
        end

        # Callbacks

        @impl Rabbit.Connection
        def init(:connection, opts) do
          # Perform any runtime configuration
          {:ok, opts}
        end
      end

      # This is an initializer
      defmodule MyInitializer do
        use Rabbit.Initializer

        def start_link(opts \\ []) do
          Rabbit.Initializer.start_link(__MODULE__, opts, name: __MODULE__)
        end

        # Callbacks

        @impl Rabbit.Initializer
        def init(_type, opts) do
          # Perform any runtime configuration
          {:ok, opts}
        end
      end

      # Start the connection
      MyConnection.start_link()

      # Start the initializer
      MyInitializer.start_link(
        connection: MyConnection,
        exchanges: [
          [name: "my_exchange_1"],
          [name: "my_exchange_2", type: :fanout],
        ],
        queues: [
          [name: "my_queue_1"],
          [name: "my_queue_2", durable: true],
        ],
        bindings: [
          [type: :queue, source: "my_exchange_1", destination: "my_queue_1"],
          [type: :exchange, source: "my_exchange_2", destination: "my_exchange_1"],
        ]
      )

  """
  alias Rabbit.Initializer

  @type t :: GenServer.name()
  @type exchange ::
          [
            {:name, binary()}
            | {:type, :direct | :fanout | :topic | :match | :headers}
            | {:durable, boolean()}
            | {:auto_delete, boolean()}
            | {:internal, boolean()}
            | {:passive, boolean()}
            | {:no_wait, boolean()}
            | {:arguments, list()}
          ]
  @type queue ::
          [
            {:name, binary()}
            | {:durable, boolean()}
            | {:auto_delete, boolean()}
            | {:exclusive, boolean()}
            | {:passive, boolean()}
            | {:no_wait, boolean()}
            | {:arguments, list()}
          ]
  @type binding ::
          [
            {:type, :queue | :exchange}
            | {:source, binary()}
            | {:destination, binary()}
            | {:routing_key, binary()}
            | {:no_wait, boolean()}
            | {:arguments, list()}
          ]
  @type option ::
          {:connection, Rabbit.Connection.t()}
          | {:retry_backoff, non_neg_integer()}
          | {:retry_max, non_neg_integer()}
          | {:queues, [queue()]}
          | {:exchanges, [exchange()]}
          | {:bindings, [binding()]}
  @type options :: [option()]

  @doc """
  A callback executed when the initializer is started.

  Returning `{:ok, opts}` - where `opts` is a keyword list of `t:option/0` will
  cause `start_link/3` to return `{:ok, pid}` and the process to enter its loop.

  Returning `:ignore` will cause `start_link/3` to return `:ignore` and the process
  will exit normally without entering the loop
  """
  @callback init(:initializer, options()) :: {:ok, options()} | :ignore

  ################################
  # Public API
  ################################

  @doc """
  Starts an initializer process.

  ## Options

    * `:connection` - A `Rabbit.Connection` process.
    * `:exchanges` - A list of exchanges to declare. Please see [Exchanges](#start_link/3-exchanges).
    * `:queues` - A list of queues to declare. Please see [Queues](#start_link/3-queues).
    * `:bindings` - A list of bindings to declare. Please see [Bindings](#start_link/3-bindings).
    * `:retry_sleep` - The amount of time in milliseconds to sleep between attempts
      to fetch a connection from the connection process - defaults to `100`.
    * `:retry_max` - The max amount of connection retries that will be attempted before
      returning an error - defaults to `25`.

  ## Exchanges

  Declaring exchanges is done by providing a list of keyword options. The options
  include:

    * `:name` - The name of the exchange.
    * `:type` - The type of the exchange - one of `:direct`, `:fanout`, `:topic`,
      `:match` or `:headers` - defaults to `:direct`.
    * `:durable` - Whether the exchange is durable across broker restarts - defaults to `false`.
    * `:auto_delete` - Deletes the exchange once all queues unbind from it - defaults to `false`.
    * `:passive` - Returns an error if the exchange does not already exist - defaults to `false`.
    * `:internal` - If set, the exchange may not be used directly by publishers, but only when
       bound to other exchanges. Internal exchanges are used to construct wiring that is not visible
       to applications - defaults to `false`.

  Below is an example of exchange options:

      [
        [name: "my_exchange_1"],
        [name: "my_exchange_2", type: :fanout, durable: true],
      ]

  ## Queues

  Declaring queues is done by providing a list of keyword options. The options
  include:

    * `:name` - The name of the queue.
    * `:durable` - Whether the queue is durable across broker restarts - defaults to `false`.
    * `:auto_delete` - Deletes the queue once all consumers disconnect - defaults to `false`.
    * `:passive` - Returns an error if the queue does not already exist - defaults to `false`.
    * `:exclusive` - If set, only one consumer can consume from the queue - defaults to `false`.

  Below is an example of queue options:

      [
        [name: "my_queue_1"],
        [name: "my_queue_2", durable: true],
      ]

  ## Bindings

  Declaring bindings is done by providing a list of keyword options. The options
  include:

    * `:type` - The type of the destination - one of `:exchange` or `:queue`.
    * `:source` - The source of the binding.
    * `:destination` - The destination of the binding.
    * `:routing_key` - The routing key of the binding.

  Below is an example of binding options:

      [
        [type: :queue, source: "my_exchange_1", destination: "my_queue_1"],
        [type: :exchange, source: "my_exchange_2", destination: "my_exchange_1"]
      ]

  ## Server Options

  You can also provide server options - which are simply the same ones available
  for `t:GenServer.options/0`.

  """
  @spec start_link(module(), list(), GenServer.options()) :: Supervisor.on_start()
  def start_link(module, opts \\ [], server_opts \\ []) do
    Initializer.Server.start_link(module, opts, server_opts)
  end

  defmacro __using__(opts) do
    quote location: :keep do
      @behaviour Rabbit.Initializer

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
