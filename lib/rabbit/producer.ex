defmodule Rabbit.Producer do
  @moduledoc false

  alias Rabbit.Producer

  @type t :: GenServer.name()
  @type start_option ::
          {:pool_size, non_neg_integer()}
          | {:max_overflow, non_neg_integer()}
          | {:sync_connect, boolean()}
          | {:publish_opts, publish_options()}
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

  @callback stop() :: :ok

  @callback init(start_options()) :: {:ok, start_options()} | :ignore

  @callback publish(exchange(), routing_key(), message(), publish_options(), timeout()) ::
              :ok | AMQP.Basic.error()

  @optional_callbacks init: 1

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

  @spec start_link(Rabbit.Connection.t(), start_options(), GenServer.options()) ::
          Supervisor.on_start()
  def start_link(connection, opts \\ [], server_opts \\ []) do
    Producer.Pool.start_link(connection, opts, server_opts)
  end

  @spec stop(Rabbit.Producer.t()) :: :ok
  def stop(producer) do
    for {_, worker, _, _} <- GenServer.call(producer, :get_all_workers) do
      :ok = GenServer.call(worker, :disconnect)
    end

    :poolboy.stop(producer)
  end

  @spec publish(
          Rabbit.Producer.t(),
          exchange(),
          routing_key(),
          message(),
          publish_options(),
          timeout()
        ) :: :ok | {:error, any()}
  def publish(producer, exchange, routing_key, payload, opts \\ [], timeout \\ 5_000) do
    message = {exchange, routing_key, payload, opts}
    :poolboy.transaction(producer, &GenServer.call(&1, {:publish, message}, timeout))
  end

  defmacro __using__(_) do
    quote do
      @behaviour Rabbit.Producer

      def child_spec(args) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, args}
        }
      end

      @impl Rabbit.Producer
      def start_link(connection, opts \\ [], server_opts \\ []) do
        opts = Keyword.put(opts, :module, __MODULE__)
        server_opts = Keyword.put(opts, :name, __MODULE__)

        Producer.start_link(connection, opts, server_opts)
      end

      @impl Rabbit.Producer
      def stop do
        Producer.stop(__MODULE__)
      end

      @impl Rabbit.Producer
      def publish(exchange, routing_key, message, opts \\ [], timeout \\ 5_000) do
        Producer.publish(__MODULE__, exchange, routing_key, message, opts, timeout)
      end
    end
  end
end
