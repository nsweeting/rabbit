defmodule Rabbit.Consumer do
  @type t :: GenServer.name()
  @type option ::
          {:queue, String.t()}
          | {:prefetch_count, non_neg_integer()}
          | {:prefetch_size, non_neg_integer()}
          | {:consumer_tag, String.t()}
          | {:no_local, boolean()}
          | {:no_ack, boolean()}
          | {:exclusive, boolean()}
          | {:no_wait, boolean()}
          | {:arguments, Keyword.t()}
  @type options :: [option()]
  @type delivery_tag :: non_neg_integer()
  @type action :: :ack | :nack | :reject
  @type action_options :: [{:multiple, boolean()} | {:requeue, boolean()}]
  @type result ::
          {action(), Rabbit.Message.t()} | {action(), Rabbit.Message.t(), action_options()}

  @callback start_link(Rabbit.Connection.t(), options()) :: Supervisor.on_start()

  @callback stop(timeout()) :: :ok | {:error, any()}

  @callback init(options()) :: {:ok, options()} | :ignore

  @callback after_connect(AMQP.Channel.t(), queue :: String.t()) :: :ok | any()

  @callback handle_message(Rabbit.Message.t()) :: result() | any()

  @callback handle_error(Rabbit.Message.t()) :: result() | any()

  @optional_callbacks init: 1, after_connect: 2

  defmacro __using__(_) do
    quote do
      @behaviour Rabbit.Consumer

      def child_spec(args) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, args}
        }
      end

      @impl Rabbit.Consumer
      def start_link(connection, opts \\ []) do
        opts = Keyword.merge(opts, name: __MODULE__, module: __MODULE__)
        Rabbit.Consumer.start_link(connection, opts)
      end

      def stop do
        Rabbit.Consumer.stop(__MODULE__)
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

  @spec start_link(Rabbit.Connection.t(), options()) :: Supervisor.on_start()
  def start_link(connection, opts \\ []) do
    Rabbit.Consumer.Server.start_link(connection, opts)
  end

  @doc false
  def stop(consumer) do
    GenServer.stop(consumer, :normal)
  end

  @doc false
  def ack(consumer, delivery_tag, opts \\ []) do
    GenServer.cast(consumer, {:ack, delivery_tag, opts})
  end

  @doc false
  def nack(consumer, delivery_tag, opts \\ []) do
    GenServer.cast(consumer, {:nack, delivery_tag, opts})
  end

  @doc false
  def reject(consumer, delivery_tag, opts \\ []) do
    GenServer.cast(consumer, {:reject, delivery_tag, opts})
  end
end
