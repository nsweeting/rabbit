defmodule Rabbit.Consumer.Worker do
  use GenServer

  require Logger

  alias Rabbit.ConsumerError

  @opts %{
    timeout: [type: :integer, default: 30_000],
    serializers: [type: :map, default: Rabbit.Serializer.defaults()]
  }

  ################################
  # Public API
  ################################

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
  def handle_cast(:complete, state) do
    {:stop, :normal, state}
  end

  @doc false
  @impl GenServer
  def handle_info({:DOWN, _, :process, _, :normal}, state) do
    {:stop, :normal, state}
  end

  @doc false
  @impl GenServer
  def handle_info(:timeout, state) do
    timeout_error(state)
    {:stop, :normal, state}
  end

  ################################
  # Private Functions
  ################################

  defp init_state(message, opts) do
    opts
    |> Enum.into(%{})
    |> Map.merge(%{
      runner: nil,
      message: message
    })
  end

  defp execute(state) do
    Process.flag(:trap_exit, true)
    handler = self()

    runner =
      spawn_link(fn ->
        try do
          message = decode_payload!(state.serializers, state.message)
          consumer_execute(state, :handle_message, [message])
        rescue
          exception ->
            error = ConsumerError.new(state.message, :exception, exception, __STACKTRACE__)
            handle_error(state, error)
        end

        GenServer.cast(handler, :complete)
      end)

    %{state | runner: runner}
  end

  defp consumer_execute(state, fun, args) do
    apply(state.message.consumer, fun, args)
  end

  defp timeout_error(state) do
    if is_pid(state.runner), do: Process.exit(state.runner, :timeout)
    error = ConsumerError.new(state.message, :error, :timeout, [])
    handle_error(state, error)
  end

  defp handle_error(state, error) do
    ConsumerError.log(error)
    consumer_execute(state, :handle_error, [error])
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
end
