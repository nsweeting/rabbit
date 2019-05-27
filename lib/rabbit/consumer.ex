defmodule Rabbit.Consumer do
  @type t :: module()
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
  @type ack_option :: {:multiple, boolean()}
  @type ack_options :: [ack_option()]
  @type nack_option :: {:multiple, boolean()} | {:requeue, boolean()}
  @type nack_options :: [nack_option()]
  @type reject_option :: {:requeue, boolean()}
  @type reject_options :: [nack_option()]
  @type action :: :ack | :nack | :reject

  @callback start_link(Rabbit.Connection.t(), options()) :: Supervisor.on_start()

  @callback init(options()) :: {:ok, options()} | :ignore

  @callback after_connect(AMQP.Channel.t(), queue :: String.t()) :: :ok | term()

  @callback handle_message(Rabbit.Message.t()) ::
              {action(), Rabbit.Message.t()}
              | {action(), Rabbit.Message.t(), Keyword.t()}
              | term()

  @callback handle_error(Rabbit.ConsumerError.t()) :: any()

  defmacro __using__(_) do
    quote do
      @behaviour Rabbit.Consumer

      def child_spec(args) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, args}
        }
      end

      def start_link(connection, opts \\ []) do
        Rabbit.Consumer.start_link(__MODULE__, connection, opts)
      end

      def init(opts) do
        {:ok, opts}
      end

      def after_connect(_channel, _queue) do
        :ok
      end

      def handle_message(message) do
        {:ack, message}
      end

      def handle_error(error) do
        {:nack, error.message}
      end

      defoverridable(init: 1, after_connect: 2, handle_message: 1, handle_error: 1)
    end
  end

  ################################
  # Public API
  ################################

  @spec start_link(Rabbit.Consumer.t(), Rabbit.Connection.t(), options()) :: Supervisor.on_start()
  def start_link(consumer, connection, opts \\ []) do
    Rabbit.Consumer.Supervisor.start_link(consumer, connection, opts)
  end

  @spec ack(Rabbit.Message.t(), ack_options()) :: :ok | {:error, any()}
  def ack(message, opts \\ []) do
    safe_call(:ack, [message, opts])
  end

  @spec nack(Rabbit.Message.t(), nack_options()) :: :ok | {:error, any()}
  def nack(message, opts \\ []) do
    safe_call(:nack, [message, opts])
  end

  @spec reject(Rabbit.Message.t(), reject_options()) :: :ok | {:error, any()}
  def reject(message, opts \\ []) do
    safe_call(:reject, [message, opts])
  end

  ################################
  # Private API
  ################################

  defp safe_call(function, args) do
    try do
      apply(Rabbit.Consumer.Server, function, args)
    catch
      msg, reason -> {:error, {msg, reason}}
    end
  end
end
