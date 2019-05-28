defmodule Rabbit.Consumer do
  import Rabbit.Utilities

  @type t :: GenServer.name()
  @type option ::
          {:queue, String.t()}
          | {:serializers, %{optional(binary) => Rabbit.Serializer.t()}}
          | {:prefetch_count, non_neg_integer()}
          | {:prefetch_size, non_neg_integer()}
          | {:consumer_tag, String.t()}
          | {:no_local, boolean()}
          | {:no_ack, boolean()}
          | {:exclusive, boolean()}
          | {:no_wait, boolean()}
          | {:arguments, Keyword.t()}
  @type options :: [option()]
  @type action :: :ack | :nack | :reject
  @type action_options :: [{:multiple, boolean()} | {:requeue, boolean()}]
  @type result ::
          {action(), Rabbit.Message.t()} | {action(), Rabbit.Message.t(), action_options()}

  @callback start_link(Rabbit.Connection.t(), options()) :: Supervisor.on_start()

  @callback init(options()) :: {:ok, options()} | :ignore

  @callback after_connect(AMQP.Channel.t(), queue :: String.t()) :: :ok | any()

  @callback handle_message(Rabbit.Message.t()) :: result() | any()

  @callback handle_error(Rabbit.Message.t()) :: result() | any()

  @optional_callbacks start_link: 2, init: 1, after_connect: 2

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

  @spec ack(Rabbit.Message.t(), action_options()) :: :ok | {:error, any()}
  def ack(message, opts \\ []) do
    safe_call(Rabbit.Consumer.Server, :ack, [message, opts])
  end

  @spec nack(Rabbit.Message.t(), action_options()) :: :ok | {:error, any()}
  def nack(message, opts \\ []) do
    safe_call(Rabbit.Consumer.Server, :nack, [message, opts])
  end

  @spec reject(Rabbit.Message.t(), action_options()) :: :ok | {:error, any()}
  def reject(message, opts \\ []) do
    safe_call(Rabbit.Consumer.Server, :reject, [message, opts])
  end
end
