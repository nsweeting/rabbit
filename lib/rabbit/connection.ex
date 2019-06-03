defmodule Rabbit.Connection do
  @moduledoc false

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
  @type options :: uri() | [option()]

  @callback start_link(options()) :: GenServer.on_start()

  @callback stop() :: :ok | {:error, any()}

  @callback init(options()) :: {:ok, options()} | :ignore

  @callback fetch() :: {:ok, Rabbit.Connection.t()} | {:error, :not_connected}

  @callback async_fetch() :: :ok

  @callback alive?() :: boolean()

  @callback subscribe(pid() | nil) :: :ok

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
  @spec async_fetch(Rabbit.Connection.t()) :: :ok
  def async_fetch(connection) do
    GenServer.call(connection, :async_fetch)
  end

  @doc false
  @spec alive?(Rabbit.Connection.t()) :: :ok
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
      def async_fetch do
        Connection.async_fetch(__MODULE__)
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
