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

  ################################
  # Public API
  ################################

  @doc false
  def start_link(connection, opts \\ []) do
    Rabbit.Connection.Server.start_link(connection, opts)
  end

  @doc false
  def subscribe(connection, subscriber \\ nil) do
    subscriber = subscriber || self()
    safe_call(:subscribe, [connection, subscriber])
  end

  @doc false
  def unsubscribe(connection, subscriber \\ nil) do
    subscriber = subscriber || self()
    safe_call(:unsubscribe, [connection, subscriber])
  end

  ################################
  # Private API
  ################################

  defp safe_call(function, args) do
    try do
      apply(Rabbit.Connection.Server, function, args)
    catch
      msg, reason -> {:error, {msg, reason}}
    end
  end
end
