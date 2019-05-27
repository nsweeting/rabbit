defmodule Rabbit.Consumer.Supervisor do
  @moduledoc false

  use Supervisor

  @opts %{
    queue: [type: :binary, required: true],
    serializers: [type: :map, default: Rabbit.Serializer.defaults()],
    prefetch_count: [type: :integer, default: 1],
    prefetch_size: [type: :integer, default: 0],
    consumer_tag: [type: :binary, default: ""],
    no_local: [type: :boolean, default: false],
    no_ack: [type: :boolean, default: false],
    exclusive: [type: :boolean, default: false],
    no_wait: [type: :boolean, default: false],
    arguments: [type: :list, default: []]
  }

  ################################
  # Public API
  ################################

  @doc false
  def start_link(consumer, connection, opts \\ []) do
    unless valid_consumer?(consumer) do
      raise ArgumentError, "#{inspect(consumer)} must export Rabbit.Consumer callbacks"
    end

    Supervisor.start_link(__MODULE__, {consumer, connection, opts})
  end

  ################################
  # Supervisor Callbacks
  ################################

  @doc false
  @impl Supervisor
  def init({consumer, connection, opts}) do
    with {:ok, opts} <- consumer_init(consumer, opts) do
      worker = Module.concat(consumer, Worker)

      opts =
        opts
        |> KeywordValidator.validate!(@opts)
        |> Keyword.put(:worker, worker)

      children = [
        {Rabbit.Consumer.WorkerSupervisor, [worker]},
        {Rabbit.Consumer.Server, [consumer, connection, opts]}
      ]

      Supervisor.init(children, strategy: :one_for_one)
    end
  end

  ################################
  # Private API
  ################################

  defp valid_consumer?(consumer) do
    export_callback?(consumer, :handle_message, 1) and
      export_callback?(consumer, :handle_error, 1)
  end

  defp export_callback?(consumer, callback, arity) do
    Code.ensure_loaded?(consumer) and function_exported?(consumer, callback, arity)
  end

  defp consumer_init(consumer, opts) do
    if export_callback?(consumer, :init, 1) do
      consumer.init(opts)
    else
      {:ok, opts}
    end
  end
end
