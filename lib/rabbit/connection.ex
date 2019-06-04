defmodule Rabbit.Connection do
  @moduledoc """
  A RabbitMQ connection process.

  This wraps around the standard `AMQP.Connection`. It provides the following
  benefits:

  * Durability during connection failures through use of expotential backoff.
  * Subscriptions that assist connection status monitoring.
  * Ability to create module-based connections that permit easy runtime setup
    through an `c:init/1` callback.

  ## Example

      # This is a connection
      defmodule MyConnection do
        use Rabbit.Connection

        # Callbacks

        # Perform any runtime configuration
        def init(opts) do
          opts = Keyword.put(opts, :uri, System.get_env("RABBIT_URI"))
          {:ok, opts}
        end
      end

      # Start the connection
      MyConnection.start_link()

      # Subscribe to the connection
      MyConnection.subscribe()

      receive do
        {:connected, connection} -> # Do stuff with AMQP.Connection
      end

      # Stop the connection
      MyConnection.stop()

      receive do
        {:disconnected, reason} -> # Do stuff with disconnect
      end

  """

  alias Rabbit.Connection

  @type t :: GenServer.name()
  @type uri :: String.t()
  @type option ::
          {:module, module()}
          | {:uri, String.t()}
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
  @type options :: uri() | [option()]

  @doc """
  Starts a RabbitMQ connection process.

  ## Options
    * `:uri` - The connection URI. This takes priority over other connection  attributes.
    * `:username` - The name of a user registered with the broker - defaults to `"guest"`.
    * `:password` - The password of user - defaults to `"guest\`.
    * `:virtual_host` - The name of a virtual host in the broker - defaults to `"/"`.
    * `:host` - The hostname of the broker - defaults to `"localhost"`.
    * `:port` - The port the broker is listening on - defaults to `5672`.
    * `:channel_max` - The channel_max handshake parameter - defaults to `0`.
    * `:frame_max` - The frame_max handshake parameter  - defaults to `0`.
    * `:heartbeat` - The hearbeat interval in seconds - defaults to `10`.
    * `:connection_timeout` - The connection timeout in milliseconds - defaults to `50000`.
    * `:ssl_options` - Enable SSL by setting the location to cert files - defaults to `:none`.
    * `:client_properties` - A list of extra client properties to be sent to the server - defaults to `[]`.
    * `:socket_options` - Extra socket options. These are appended to the default options. \
      See http://www.erlang.org/doc/man/inet.html#setopts-2 and http://www.erlang.org/doc/man/gen_tcp.html#connect-4 \
      for descriptions of the available options.

  """
  @callback start_link(options()) :: GenServer.on_start()

  @doc """
  Stops a RabbitMQ connection process.
  """
  @callback stop() :: :ok | {:error, any()}

  @callback init(options()) :: {:ok, options()} | :ignore

  @doc """
  Fetches the raw `AMQP.Connection` struct from the process.
  """
  @callback fetch() :: {:ok, Rabbit.Connection.t()} | {:error, :not_connected}

  @doc """
  Checks whether a connection is alive.
  """
  @callback alive?() :: boolean()

  @doc """
  Subscribes a process to the RabbitMQ connection.

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
  @callback subscribe(subscriber :: pid() | nil) :: :ok

  @optional_callbacks init: 1

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
  @spec start_link(options(), GenServer.options()) :: GenServer.on_start()
  def start_link(opts \\ [], server_opts \\ []) do
    Connection.Server.start_link(opts, server_opts)
  end

  @doc false
  @spec stop(Rabbit.Connection.t()) :: :ok
  def stop(connection) do
    GenServer.stop(connection, :normal)
  end

  @doc false
  @spec fetch(Rabbit.Connection.t()) :: {:ok, AMQP.Connection.t()} | {:error, :no_connection}
  def fetch(connection) do
    GenServer.call(connection, :fetch)
  end

  @doc false
  @spec alive?(Rabbit.Connection.t()) :: boolean()
  def alive?(connection) do
    GenServer.call(connection, :alive?)
  end

  @doc false
  @spec subscribe(Rabbit.Connection.t(), pid() | nil) :: :ok
  def subscribe(connection, subscriber \\ nil) do
    subscriber = subscriber || self()
    GenServer.call(connection, {:subscribe, subscriber})
  end

  defmacro __using__(_) do
    quote do
      @behaviour Rabbit.Connection

      def child_spec(opts) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, opts}
        }
      end

      @impl Rabbit.Connection
      def start_link(opts \\ [], server_opts \\ []) do
        opts = Keyword.put(opts, :module, __MODULE__)
        server_opts = Keyword.put(server_opts, :name, __MODULE__)

        Connection.start_link(opts, server_opts)
      end

      @impl Rabbit.Connection
      def stop do
        Connection.stop(__MODULE__)
      end

      @impl Rabbit.Connection
      def fetch do
        Connection.fetch(__MODULE__)
      end

      @impl Rabbit.Connection
      def alive? do
        Connection.alive?(__MODULE__)
      end

      @impl Rabbit.Connection
      def subscribe(subscriber \\ nil) do
        Connection.subscribe(__MODULE__, subscriber)
      end
    end
  end
end
