defmodule Rabbit.Producer do
  import Rabbit.Utilities

  @type t :: GenServer.name()
  @type start_option ::
          {:connection, Rabbit.Connection.t()}
          | {:pool_size, non_neg_integer()}
          | {:max_overflow, non_neg_integer()}
  @type start_options :: [start_option()]
  @type exchange :: String.t()
  @type routing_key :: String.t()
  @type message :: term()
  @type publish_option ::
          {:mandatory, boolean()}
          | {:immediate, boolean()}
          | {:content_type, String.t()}
          | {:content_encoding, String.t()}
          | {:headers, [{String.t(), String.t()}]}
          | {:persistent, boolean()}
          | {:correlation_id, String.t()}
          | {:priority, 1..9}
          | {:reply_to, String.t()}
          | {:expiration, non_neg_integer()}
          | {:message_id, String.t()}
          | {:timestamp, non_neg_integer()}
          | {:type, String.t()}
          | {:user_id, String.t()}
          | {:app_id, String.t()}
  @type publish_options :: [publish_option()]

  @callback start_link(Rabbit.Connection.t(), start_options()) :: Supervisor.on_start()

  @callback stop(timeout()) :: :ok | {:error, any()}

  @callback init(start_options()) :: {:ok, start_options()} | :ignore

  @callback publish(exchange(), routing_key(), message(), publish_options(), timeout()) ::
              :ok | AMQP.Basic.error()

  @optional_callbacks init: 1

  defmacro __using__(_) do
    quote do
      @behaviour Rabbit.Producer

      def child_spec(args) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, args},
          type: :supervisor
        }
      end

      @impl Rabbit.Producer
      def start_link(connection, opts \\ []) do
        opts = Keyword.merge(opts, name: __MODULE__, module: __MODULE__)
        Rabbit.Producer.start_link(connection, opts)
      end

      @impl Rabbit.Producer
      def stop(timeout \\ 5_000) do
        Rabbit.Producer.stop(__MODULE__, timeout)
      end

      @impl Rabbit.Producer
      def publish(exchange, routing_key, message, opts \\ [], timeout \\ 5_000) do
        Rabbit.Producer.publish(__MODULE__, exchange, routing_key, message, opts, timeout)
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
      start: {__MODULE__, :start_link, args},
      type: :supervisor
    }
  end

  @spec start_link(Rabbit.Connection.t(), start_options()) :: Supervisor.on_start()
  def start_link(connection, opts \\ []) do
    Rabbit.Producer.Pool.start_link(connection, opts)
  end

  @spec publish(
          Rabbit.Producer.t(),
          exchange(),
          routing_key(),
          message(),
          publish_options(),
          timeout()
        ) :: :ok | {:error, any()}
  def publish(producer, exchange, routing_key, message, opts \\ [], timeout \\ 5_000) do
    args = [producer, exchange, routing_key, message, opts, timeout]
    safe_call(Rabbit.Producer.Pool, :publish, args)
  end
end
