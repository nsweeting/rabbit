defmodule Rabbit.Connection do
  @type t :: module() | atom()
  @type uri :: String.t()
  @type option ::
          {:username, String.t()}
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

  @callback init(options()) :: {:ok, options()} | :ignore

  @callback subscribe(pid() | nil) :: :ok

  @callback unsubscribe(pid() | nil) :: :ok

  defmacro __using__(_) do
    quote do
      @behaviour Rabbit.Connection

      def child_spec(args) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, args}
        }
      end

      @impl Rabbit.Connection
      def start_link(opts \\ []) do
        Rabbit.Connection.start_link(__MODULE__, opts)
      end

      @impl Rabbit.Connection
      def init(opts) do
        {:ok, opts}
      end

      @impl Rabbit.Connection
      def subscribe(subscriber \\ nil) do
        Rabbit.Connection.subscribe(__MODULE__, subscriber)
      end

      @impl Rabbit.Connection
      def unsubscribe(subscriber \\ nil) do
        Rabbit.Connection.unsubscribe(__MODULE__, subscriber)
      end

      defoverridable(init: 1)
    end
  end

  @spec start_link(Rabbit.Connection.t(), Rabbit.Connection.options()) :: GenServer.on_start()
  def start_link(connection, opts \\ []) do
    Rabbit.Connection.Worker.start_link(connection, opts)
  end

  @spec subscribe(Rabbit.Connection.t(), pid() | nil) :: :ok
  def subscribe(connection, subscriber \\ nil) do
    Rabbit.Connection.Worker.subscribe(connection, subscriber)
  end

  @spec unsubscribe(Rabbit.Connection.t(), pid() | nil) :: :ok
  def unsubscribe(connection, subscriber \\ nil) do
    Rabbit.Connection.Worker.unsubscribe(connection, subscriber)
  end

  @doc false
  def valid?(connection) when is_atom(connection) do
    Code.ensure_loaded?(connection) and
      connection.module_info[:attributes]
      |> Keyword.get(:behaviour, [])
      |> Enum.member?(__MODULE__)
  end

  def valid?(_) do
    false
  end
end
