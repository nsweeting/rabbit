defmodule Rabbit.ConsumerError do
  require Logger

  defexception [:message, :kind, :reason, :stack]

  @type t :: %__MODULE__{}

  def new(message, kind, reason, stack) do
    %__MODULE__{
      message: message,
      kind: kind,
      reason: reason,
      stack: stack
    }
  end

  def log(error) do
    Logger.error("""
    #{inspect(error.message.consumer)}: consumer error.

    Reason:
        #{do_inspect(error.reason)}

    Payload:
        #{do_payload(error.message)}

    Consumer:
        - Queue: #{error.message.meta.routing_key}
        - PID: #{inspect(self())}
    #{do_stacktrace(error.stack)}
    """)
  end

  defp do_inspect(arg) do
    inspect(arg, pretty: true, width: 100)
  end

  defp do_payload(%{assigns: %{decoded_payload: payload}}) do
    do_inspect(payload)
  end

  defp do_payload(message) do
    do_inspect(message.payload)
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
