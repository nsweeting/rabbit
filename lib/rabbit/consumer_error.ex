defmodule Rabbit.ConsumerError do
  @moduledoc false

  require Logger

  defexception [:message, :kind, :reason, :stack]

  @type t :: %__MODULE__{}

  @doc false
  def new(message, kind, reason, stack) do
    %__MODULE__{
      message: message,
      kind: kind,
      reason: reason,
      stack: stack
    }
  end

  @doc false
  def log(error) do
    Logger.error("""
    #{inspect(error.message.consumer)}: worker error.

    Reason:
        #{do_inspect(error.reason)}

    Payload:
        #{do_payload(error.message)}

    Consumer:
        - Worker: #{inspect(self())}
        - Exchange: #{error.message.meta.exchange}
        - Routing key: #{error.message.meta.routing_key}

    #{do_stacktrace(error.stack)}
    """)
  end

  defp do_inspect(arg) do
    inspect(arg, pretty: true, width: 100)
  end

  defp do_payload(%{payload: payload, decoded_payload: nil}) do
    do_inspect(payload)
  end

  defp do_payload(%{payload: payload}) do
    do_inspect(payload)
  end

  defp do_stacktrace([]) do
    nil
  end

  defp do_stacktrace(stack) do
    """

    Stacktrace:
    #{Exception.format_stacktrace(stack)}
    """
  end
end
