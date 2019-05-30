defmodule Rabbit.Connection do
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

  @callback stop(timeout()) :: :ok | {:error, any()}

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
        Rabbit.Connection.start_link(opts)
      end

      @impl Rabbit.Connection
      def stop do
        Rabbit.Connection.stop(__MODULE__)
      end

      @impl Rabbit.Connection
      def subscribe(subscriber \\ nil) do
        Rabbit.Connection.subscribe(__MODULE__, subscriber)
      end

      @impl Rabbit.Connection
      def alive? do
        Rabbit.Connection.alive?(__MODULE__)
      end

      @impl Rabbit.Connection
      def unsubscribe(subscriber \\ nil) do
        Rabbit.Connection.unsubscribe(__MODULE__, subscriber)
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
  def start_link(opts \\ []) do
    Rabbit.Connection.Server.start_link(opts)
  end

  @doc false
  def stop(connection) do
    Rabbit.Connection.Server.stop(connection)
  end

  @spec alive?(Rabbit.Connection.t(), timeout()) :: boolean()
  def alive?(connection, timeout \\ 5_000) do
    Rabbit.Connection.Server.alive?(connection, timeout)
  end

  @doc false
  def subscribe(connection, subscriber \\ nil) do
    subscriber = subscriber || self()
    Rabbit.Connection.Server.subscribe(connection, subscriber)
  end

  @doc false
  def unsubscribe(connection, subscriber \\ nil) do
    subscriber = subscriber || self()
    Rabbit.Connection.Server.unsubscribe(connection, subscriber)
  end
end
