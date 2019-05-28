defmodule Rabbit.Message do
  defstruct [
    :consumer,
    :module,
    :channel,
    :payload,
    :decoded_payload,
    :meta,
    :error_reason,
    :error_stack
  ]

  @type t :: %__MODULE__{}

  @spec new(Rabbit.Consumer.t(), module(), AMQP.Channel.t(), any(), map()) :: Rabbit.Message.t()
  def new(consumer, module, channel, payload, meta) do
    %__MODULE__{
      consumer: consumer,
      module: module,
      channel: channel,
      payload: payload,
      meta: meta
    }
  end

  @spec put_error(Rabbit.Message.t(), any(), list()) :: Rabbit.Message.t()
  def put_error(message, reason, stack) do
    %{message | error_reason: reason, error_stack: stack}
  end
end
