defmodule Rabbit.ConnectionPool do
  @moduledoc """
  A RabbitMQ connection pool process.

  This mirrors the API of the `Rabbit.Connection` module, except is creates a
  pool of connection processes. It provides all the same connection guarantees as
  `Rabbit.Connection`.

  ## Example

      # Connection module
      defmodule MyConnectionPool do
        use Rabbit.ConnectionPool

        def start_link(opts \\\\ []) do
          Rabbit.ConnectionPool.start_link(__MODULE__, opts, name: __MODULE__)
        end

        # Callbacks

        @impl Rabbit.ConnectionPool
        def init(:connection_pool, opts) do
          # Perform any runtime pool configuration
          {:ok, opts}
        end

        def init(:connection, opts) do
          # Perform any runtime connection configuration
          {:ok, opts}
        end
      end

      # Start the connection pool
      MyConnectionPool.start_link()

      # Subscribe to a connection in the pool
      Rabbit.ConnectionPool.subscribe(MyConnectionPool)

      receive do
        {:connected, connection} -> "hello"
      end

      # Stop the connection pool
      Rabbit.ConnectionPool.stop(MyConnectionPool)

      receive do
        {:disconnected, reason} -> "bye"
      end

  """

  alias Rabbit.Connection

  @type t :: GenServer.name()
  @type option ::
          {:pool_size, non_neg_integer()}
          | {:max_overflow, non_neg_integer()}
          | {:strategy, :lifo | :fifo}
          | Rabbit.Connection.option()
  @type options :: [option()]

  @doc """
  A callback executed by each component of the connection pool.

  Two versions of the callback must be created. One for the pool, and one
  for the connections. The first argument differentiates the callback.

        # Initialize the pool
        def init(:connection_pool, opts) do
          {:ok, opts}
        end

        # Initialize a single connection
        def init(:connection, opts) do
          {:ok, opts}
        end

  Returning `{:ok, opts}` - where `opts` is a keyword list of `t:option()` will,
  cause `start_link/3` to return `{:ok, pid}` and the process to enter its loop.

  Returning `:ignore` will cause `start_link/3` to return `:ignore` and the process
  will exit normally without entering the loop
  """
  @callback init(:connection_pool | :connection, options()) :: {:ok, options()} | :ignore

  ################################
  # Public API
  ################################

  @doc """
  Starts a connection pool process.

  ## Options

    * `:pool_size` - The number of processes to create for connections - defaults to `1`.
      Each process consumes a RabbitMQ connection.
    * `:max_overflow` - Maximum number of temporary workers created when the pool
      is empty - defaults to `0`.
    * `:stratgey` - Determines whether checked in workers should be placed first
      or last in the line of available workers - defaults to `:fifo`.

  ## Connection Options

  You can also provide connection options - which are simply the same ones
  available for `t:Rabbit.Connection.options/0`.

  ## Server Options

  You can also provide server options - which are simply the same ones available
  for `t:GenServer.options/0`.

  """
  @spec start_link(module(), options(), GenServer.options()) :: GenServer.on_start()
  def start_link(module, opts \\ [], server_opts \\ []) do
    Connection.Pool.start_link(module, opts, server_opts)
  end

  @doc """
  Stops the connection pool.
  """
  @spec stop(Rabbit.ConnectionPool.t()) :: :ok
  def stop(connection_pool) do
    for {_, worker, _, _} <- GenServer.call(connection_pool, :get_all_workers) do
      :ok = GenServer.call(worker, :disconnect)
    end

    :poolboy.stop(connection_pool)
  end

  @doc """
  Fetches a raw `AMQP.Connection` struct from the pool.
  """
  @spec fetch(Rabbit.ConnectionPool.t(), timeout()) ::
          {:ok, AMQP.Connection.t()} | {:error, :not_connected}
  def fetch(connection_pool, timeout \\ 5_000) do
    :poolboy.transaction(connection_pool, &GenServer.call(&1, :fetch, timeout))
  end

  @doc """
  Checks whether a connection is alive within the pool.
  """
  @spec alive?(Rabbit.ConnectionPool.t(), timeout()) :: boolean()
  def alive?(connection_pool, timeout \\ 5_000) do
    :poolboy.transaction(connection_pool, &GenServer.call(&1, :alive?, timeout))
  end

  @doc """
  Runs the given function inside a transaction.

  The function must accept a connection pid.
  """
  @spec transaction(Rabbit.ConnectionPool.t(), (Rabbit.Connection.t() -> any())) :: any()
  def transaction(connection_pool, fun) do
    :poolboy.transaction(connection_pool, &fun.(&1))
  end

  @doc """
  Subscribes a process to a connection in the pool.

  A subscribed process can receive the following messages:

  `{:connected, connection}` - where connection is an `AMQP.Connection` struct.

  During the subscription process, if the connection is alive, this message will
  immediately be sent. If the connection goes down, and manages to reconnect, this
  message will be sent.

  `{:disconnected, reason}` - where reason can be any value.

  If the connection goes down, all subscribing processes are sent this message.
  The connection process will then go through an exponential backoff period until
  connection is achieved again.

  """
  @spec subscribe(Rabbit.ConnectionPool.t(), pid() | nil, timeout()) :: :ok
  def subscribe(connection_pool, subscriber \\ nil, timeout \\ 5_000) do
    subscriber = subscriber || self()
    :poolboy.transaction(connection_pool, &GenServer.call(&1, {:subscribe, subscriber}, timeout))
  end

  defmacro __using__(opts) do
    quote location: :keep do
      @behaviour Rabbit.ConnectionPool

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
