defmodule Rabbit.Connection do
  @moduledoc false

  alias Rabbit.Connection

  @type t :: GenServer.name()
  @type uri :: String.t()
  @type option ::
          {:module, module()}
          | {:name, GenServer.name()}
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

  @callback alive?() :: boolean()

  @callback subscribe(pid() | nil) :: :ok

  @callback unsubscribe(pid() | nil) :: :ok

  @optional_callbacks init: 1

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
      def start_link(opts \\ []) do
        opts = Keyword.merge(opts, name: __MODULE__, module: __MODULE__)
        Connection.start_link(opts)
      end

      @impl Rabbit.Connection
      def stop do
        Connection.stop(__MODULE__)
      end

      @impl Rabbit.Connection
      def alive? do
        Connection.alive?(__MODULE__)
      end

      @impl Rabbit.Connection
      def subscribe(subscriber \\ nil) do
        Connection.subscribe(__MODULE__, subscriber)
      end

      @impl Rabbit.Connection
      def unsubscribe(subscriber \\ nil) do
        Connection.unsubscribe(__MODULE__, subscriber)
      end
    end
  end

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
  @spec start_link(options()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    Connection.Server.start_link(opts)
  end

  @doc false
  @spec stop(Rabbit.Connection.t()) :: :ok
  def stop(connection) do
    GenServer.stop(connection, :normal)
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

  @doc false
  @spec unsubscribe(Rabbit.Connection.t(), pid() | nil) :: :ok
  def unsubscribe(connection, subscriber \\ nil) do
    subscriber = subscriber || self()
    GenServer.call(connection, {:unsubscribe, subscriber})
  end
end
