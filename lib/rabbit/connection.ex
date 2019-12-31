defmodule Rabbit.Connection do
  @moduledoc """
  A RabbitMQ connection process.

  Connections form the basis of any application that is working with RabbitMQ. A
  connection module is needed by all the other modules included with Rabbit. They
  wrap around the standard `AMQP.Connection` and provide the following
  benefits:

  * Durability during connection failures through use of expotential backoff.
  * Subscriptions that assist connection status monitoring.
  * Easy runtime setup through an `c:init/2` callback.

  ## Example

      # Connection module
      defmodule MyConnection do
        use Rabbit.Connection

        def start_link(opts \\\\ []) do
          Rabbit.Connection.start_link(__MODULE__, opts, name: __MODULE__)
        end

        # Callbacks

        @impl Rabbit.Connection
        def init(_type, opts) do
          # Perform any runtime configuration
          {:ok, opts}
        end
      end

      # Start the connection
      MyConnection.start_link()

      # Subscribe to the connection
      Rabbit.Connection.subscribe(MyConnection)

      receive do
        {:connected, connection} -> "hello"
      end

      # Stop the connection
      Rabbit.Connection.stop(MyConnection)

      receive do
        {:disconnected, reason} -> "bye"
      end

  """

  alias Rabbit.Connection

  @type t :: GenServer.name()
  @type option ::
          {:uri, String.t()}
          | {:name, String.t()}
          | {:username, String.t()}
          | {:password, String.t()}
          | {:virtual_host, String.t()}
          | {:host, String.t()}
          | {:port, integer()}
          | {:channel_max, integer()}
          | {:frame_max, integer()}
          | {:heartbeat, integer()}
          | {:connection_timeout, integer()}
          | {:ssl_options, atom() | Keyword.t()}
          | {:socket_options, Keyword.t()}
          | {:retry_backoff, non_neg_integer()}
          | {:retry_max_delay, non_neg_integer()}
          | {:pool_size, non_neg_integer()}
          | {:max_overflow, non_neg_integer()}
          | {:strategy, :lifo | :fifo}
  @type options :: [option()]
  @type connection_option ::
          {:uri, String.t()}
          | {:name, String.t()}
          | {:username, String.t()}
          | {:password, String.t()}
          | {:virtual_host, String.t()}
          | {:host, String.t()}
          | {:port, integer()}
          | {:channel_max, integer()}
          | {:frame_max, integer()}
          | {:heartbeat, integer()}
          | {:connection_timeout, integer()}
          | {:ssl_options, atom() | Keyword.t()}
          | {:socket_options, Keyword.t()}
          | {:retry_backoff, non_neg_integer()}
          | {:retry_max_delay, non_neg_integer()}
  @type connection_options :: [connection_option()]
  @type pool_option ::
          {:pool_size, non_neg_integer()}
          | {:max_overflow, non_neg_integer()}
          | {:strategy, :lifo | :fifo}
  @type pool_options :: [pool_option()]

  @doc """
  A callback executed by each component of the connection.

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
  @callback init(:connection_pool | :connection, options()) ::
              {:ok, pool_options() | connection_options()} | :ignore

  ################################
  # Public API
  ################################

  @doc """
  Starts a connection process.

  ## Options

    * `:uri` - The connection URI. This takes priority over other connection attributes.
    * `:name` - A name that will be displayed in the management UI.
    * `:username` - The name of a user registered with the broker - defaults to `"guest"`.
    * `:password` - The password of user - defaults to `"guest\`.
    * `:virtual_host` - The name of a virtual host in the broker - defaults to `"/"`.
    * `:host` - The hostname of the broker - defaults to `"localhost"`.
    * `:port` - The port the broker is listening on - defaults to `5672`.
    * `:channel_max` - The channel_max handshake parameter - defaults to `0`.
    * `:frame_max` - The frame_max handshake parameter  - defaults to `0`.
    * `:heartbeat` - The hearbeat interval in seconds - defaults to `10`.
    * `:connection_timeout` - The connection timeout in milliseconds - defaults to `50000`.
    * `:retry_backoff` - The amount of time in milliseconds to add between connection retry
      attempts - defaults to `1_000`.
    * `:retry_max_delay` - The max amount of time in milliseconds to be used between
      connection attempts - defaults to `5_000`.
    * `:ssl_options` - Enable SSL by setting the location to cert files - defaults to `:none`.
    * `:client_properties` - A list of extra client properties to be sent to the server - defaults to `[]`.
    * `:socket_options` - Extra socket options. These are appended to the default options. \
      See http://www.erlang.org/doc/man/inet.html#setopts-2 and http://www.erlang.org/doc/man/gen_tcp.html#connect-4 \
      for descriptions of the available options.
    * `:pool_size` - The number of processes to create for connections - defaults to `1`.
      Each process consumes a RabbitMQ connection.
    * `:max_overflow` - Maximum number of temporary workers created when the pool
      is empty - defaults to `0`.
    * `:stratgey` - Determines whether checked in workers should be placed first
      or last in the line of available workers - defaults to `:fifo`.

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
  @spec stop(Rabbit.Connection.t()) :: :ok
  def stop(connection) do
    for {_, worker, _, _} <- GenServer.call(connection, :get_all_workers) do
      :ok = GenServer.call(worker, :disconnect)
    end

    :poolboy.stop(connection)
  end

  @doc """
  Fetches a raw `AMQP.Connection` struct from the pool.
  """
  @spec fetch(Rabbit.Connection.t(), timeout()) ::
          {:ok, AMQP.Connection.t()} | {:error, :not_connected}
  def fetch(connection, timeout \\ 5_000) do
    :poolboy.transaction(connection, &GenServer.call(&1, :fetch, timeout))
  end

  @doc """
  Checks whether a connection is alive within the pool.
  """
  @spec alive?(Rabbit.Connection.t(), timeout()) :: boolean()
  def alive?(connection, timeout \\ 5_000) do
    :poolboy.transaction(connection, &GenServer.call(&1, :alive?, timeout))
  end

  @doc """
  Runs the given function inside a transaction.

  The function must accept a connection pid.
  """
  @spec transaction(Rabbit.Connection.t(), (Rabbit.Connection.t() -> any())) :: any()
  def transaction(connection, fun) do
    :poolboy.transaction(connection, &fun.(&1))
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
  @spec subscribe(Rabbit.Connection.t(), pid() | nil, timeout()) :: :ok
  def subscribe(connection, subscriber \\ nil, timeout \\ 5_000) do
    subscriber = subscriber || self()
    :poolboy.transaction(connection, &GenServer.call(&1, {:subscribe, subscriber}, timeout))
  end

  defmacro __using__(opts) do
    quote location: :keep do
      @behaviour Rabbit.Connection

      if Module.get_attribute(__MODULE__, :doc) == nil do
        @doc """
        Returns a specification to start this connection under a supervisor.
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
