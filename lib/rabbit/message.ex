defmodule Rabbit.Message do
  @moduledoc """
  A message consumed by a `Rabbit.Consumer`.

  After starting a consumer, any message passed to the `c:Rabbit.Consumer.handle_message/1`
  callback will be wrapped in a messsage struct. The struct has the following
  fields:

  * `:consumer` - The PID of the consumer process.
  * `:module` - The module of the consumer process.
  * `:channel` - The `AMQP.Channel` being used by the consumer.
  * `:payload` - The raw payload of the message.
  * `:decoded_payload` - If the message has a content type - this will be the
    payload decoded using the applicable serializer.
  * `:meta` - The metadata sent when publishing or set by the broker.
  * `:error_reason` - The reason for any error that occurs during the message
    handling callback.
  * `:error_stack` - The stacktrace that might accompany the error.

  """

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

  @type t :: %__MODULE__{
          consumer: pid(),
          module: module(),
          channel: AMQP.Channel.t(),
          payload: binary(),
          decoded_payload: any(),
          meta: map(),
          error_reason: any(),
          error_stack: nil | list()
        }

  @doc """
  Creates a new message struct.
  """
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

  @doc false
  @spec put_error(Rabbit.Message.t(), any(), list()) :: Rabbit.Message.t()
  def put_error(message, reason, stack) do
    %{message | error_reason: reason, error_stack: stack}
  end
end
