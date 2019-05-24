defmodule Rabbit.Consumer do
  @type t :: module()
  @type option ::
          {:connection, Rabbit.Connection.t()}
          | {:serializers, %{optional(binary) => Rabbit.Serializer.t()}}
  @type options :: [option()]

  @callback start_link(options()) :: Supervisor.on_start()

  @callback init(options()) :: {:ok, options()} | :ignore

  @callback handle_message(Rabbit.Message.t()) :: any()

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

      defoverridable(init: 1)
    end
  end

  @spec start_link(Rabbit.Consumer.t(), Rabbit.Connection.t(), options()) :: Supervisor.on_start()
  def start_link(consumer, connection, opts \\ []) do
    Rabbit.Consumer.Supervisor.start_link(consumer, connection, opts)
  end

  defdelegate ack(message, opts \\ []), to: Rabbit.Consumer.Worker
end
