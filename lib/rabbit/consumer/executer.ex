defmodule Rabbit.Consumer.Executer do
  @moduledoc false

  use GenServer

  import Rabbit.Utilities

  require Logger

  alias Rabbit.Message

  @opts_schema KeywordValidator.schema!(timeout: [is: :integer, default: 60_000])

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
    GenServer.start_link(__MODULE__, {message, opts})
  end

  ################################
  # GenServer Callbacks
  ################################

  @doc false
  @impl GenServer
  def init({message, opts}) do
    Process.flag(:trap_exit, true)

    with {:ok, opts} <- validate_opts(opts, @opts_schema) do
      state = init_state(message, opts)
      set_timeout(state.timeout)
      {:ok, state, {:continue, :run}}
    end
  end

  @doc false
  @impl GenServer
  def handle_continue(:run, state) do
    state = run(state)
    {:noreply, state, state.timeout}
  end

  @doc false
  @impl GenServer
  def handle_info(:timeout, state) do
    if is_pid(state.executer), do: Process.exit(state.executer, :normal)
    handle_error(state, {:exit, :timeout}, [])
    {:stop, :timeout, state}
  end

  def handle_info({:EXIT, pid1, reason}, %{executer: pid2} = state) when pid1 == pid2 do
    {reason, stack} =
      case reason do
        {%_{} = reason, stack} -> {reason, stack}
        reason -> {reason, []}
      end

    handle_error(state, reason, stack)
    {:stop, reason, state}
  end

  @doc false
  @impl GenServer
  def handle_cast({:complete, ref1}, %{executer_ref: ref2} = state) when ref1 == ref2 do
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
      executer_ref: nil,
      message: message
    })
  end

  defp set_timeout(:infinite) do
    :ok
  end

  defp set_timeout(timeout) do
    Process.send_after(self(), :timeout, timeout)
  end

  defp run(state) do
    parent = self()
    ref = make_ref()

    executer =
      spawn_link(fn ->
        try do
          message = decode_payload!(state.message)
          consumer_callback(state, :handle_message, [message])
        rescue
          exception -> handle_error(state, exception, __STACKTRACE__)
        catch
          msg, reason -> handle_error(state, {msg, reason}, __STACKTRACE__)
        end

        GenServer.cast(parent, {:complete, ref})
      end)

    %{state | executer: executer, executer_ref: ref}
  end

  defp decode_payload!(message) do
    with {:ok, serializers} <- Rabbit.Config.get(:serializers),
         {:ok, serializer} <- Map.fetch(serializers, message.meta.content_type) do
      payload = Rabbit.Serializer.decode!(serializer, message.payload)
      %{message | decoded_payload: payload}
    else
      _ -> message
    end
  end

  defp consumer_callback(state, fun, args) do
    state.message.module
    |> apply(fun, args)
    |> handle_result()
  end

  defp handle_result({:ack, message}), do: Message.ack(message)
  defp handle_result({:ack, message, opts}), do: Message.ack(message, opts)
  defp handle_result({:nack, message}), do: Message.nack(message)
  defp handle_result({:nack, message, opts}), do: Message.nack(message, opts)
  defp handle_result({:reject, message}), do: Message.reject(message)
  defp handle_result({:reject, message, opts}), do: Message.reject(message, opts)
  defp handle_result(other), do: other

  defp handle_error(state, reason, stack) do
    message = Rabbit.Message.put_error(state.message, reason, stack)
    log_error(message)
    consumer_callback(state, :handle_error, [message])
  end

  defp log_error(message) do
    Logger.error("""
    [Rabbit.Consumer] #{inspect(message.consumer)}: executer error.

    Reason:
        #{log_inspect(message.error_reason)}

    Payload:
        #{log_error_payload(message)}

    Consumer:
        - Module: #{inspect(message.module)}
        - Executer: #{inspect(self())}
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
