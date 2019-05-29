defmodule Rabbit.Runner do
  @moduledoc false

  use GenServer

  require Logger

  @opts %{
    timeout: [type: :integer, default: 30_000],
    serializers: [type: :map, default: Rabbit.Serializer.defaults()]
  }

  ################################
  # Public API
  ################################

  @doc false
  def child_spec(args) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, args},
      restart: :temporary
    }
  end

  @spec start_link(Rabbit.Message.t(), keyword()) :: GenServer.on_start()
  def start_link(message, opts \\ []) do
    opts = KeywordValidator.validate!(opts, @opts)
    GenServer.start_link(__MODULE__, {message, opts})
  end

  ################################
  # GenServer Callbacks
  ################################

  @doc false
  @impl GenServer
  def init({message, opts}) do
    state = init_state(message, opts)
    set_timeout(state.timeout)
    {:ok, state, {:continue, :execute}}
  end

  @doc false
  @impl GenServer
  def handle_continue(:execute, state) do
    state = execute(state)
    {:noreply, state, state.timeout}
  end

  @doc false
  @impl GenServer
  def handle_info(:timeout, state) do
    if is_pid(state.executer), do: Process.exit(state.executer, :timeout)
    {:noreply, state}
  end

  def handle_info({:EXIT, _, _}, state) do
    {:stop, :normal, state}
  end

  ################################
  # Private Functions
  ################################

  defp init_state(message, opts) do
    opts
    |> Enum.into(%{})
    |> Map.merge(%{
      executer: nil,
      message: message
    })
  end

  defp set_timeout(:infinite) do
    :ok
  end

  defp set_timeout(timeout) do
    Process.send_after(self(), :timeout, timeout)
  end

  defp execute(state) do
    Process.flag(:trap_exit, true)

    executer =
      spawn_link(fn ->
        try do
          message = decode_payload!(state.serializers, state.message)
          consumer_callback(state, :handle_message, [message])
        rescue
          exception -> handle_error(state, exception, __STACKTRACE__)
        catch
          msg, reason -> handle_error(state, {msg, reason}, __STACKTRACE__)
        end
      end)

    %{state | executer: executer}
  end

  defp decode_payload!(serializers, message) do
    case Map.fetch(serializers, message.meta.content_type) do
      {:ok, serializer} ->
        payload = Rabbit.Serializer.decode!(serializer, message.payload)
        %{message | decoded_payload: payload}

      _ ->
        message
    end
  end

  defp consumer_callback(state, fun, args) do
    apply(state.message.module, fun, args) |> handle_result()
  end

  defp handle_result({:ack, message}), do: Rabbit.Consumer.ack(message)
  defp handle_result({:ack, message, opts}), do: Rabbit.Consumer.ack(message, opts)
  defp handle_result({:nack, message}), do: Rabbit.Consumer.nack(message)
  defp handle_result({:nack, message, opts}), do: Rabbit.Consumer.nack(message, opts)
  defp handle_result({:reject, message}), do: Rabbit.Consumer.reject(message)
  defp handle_result({:reject, message, opts}), do: Rabbit.Consumer.reject(message, opts)
  defp handle_result(other), do: other

  defp handle_error(state, reason, stack) do
    message = Rabbit.Message.put_error(state.message, reason, stack)
    log_error(message)
    consumer_callback(state, :handle_error, [message])
  end

  defp log_error(message) do
    Logger.error("""
    #{inspect(message.consumer)}: worker error.

    Reason:
        #{log_inspect(message.error_reason)}

    Payload:
        #{log_error_payload(message)}

    Consumer:
        - Module: #{inspect(message.module)}
        - Worker: #{inspect(self())}
        - Exchange: #{message.meta.exchange}
        - Routing key: #{message.meta.routing_key}

    #{log_error_stack(message.error_stack)}
    """)
  end

  defp log_inspect(arg) do
    inspect(arg, pretty: true, width: 100)
  end

  defp log_error_payload(%{payload: payload, decoded_payload: nil}) do
    log_inspect(payload)
  end

  defp log_error_payload(%{payload: payload}) do
    log_inspect(payload)
  end

  defp log_error_stack([]) do
    nil
  end

  defp log_error_stack(stack) do
    """

    Stacktrace:
    #{Exception.format_stacktrace(stack)}
    """
  end
end
