defmodule Rabbit.Consumer.Supervisor do
  @moduledoc false

  use Supervisor

  alias Rabbit.Consumer.{HandlerSupervisor, Worker}

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
    arguments: [type: :list, default: []],
    durable: [type: :boolean, default: false],
    passive: [type: :boolean, default: false],
    auto_delete: [type: :boolean, default: false]
  }

  ################################
  # Public API
  ################################

  @doc false
  def start_link(consumer, connection, opts \\ []) do
    Supervisor.start_link(__MODULE__, {consumer, connection, opts})
  end

  ################################
  # Supervisor Callbacks
  ################################

  @doc false
  @impl Supervisor
  def init({consumer, connection, opts}) do
    with {:ok, opts} <- consumer_init(consumer, opts) do
      handler = handler_name(consumer)

      opts =
        opts
        |> KeywordValidator.validate!(@opts)
        |> Keyword.put(:handler, handler)

      children = [
        {Worker, [consumer, connection, opts]},
        {HandlerSupervisor, [handler]}
      ]

      Supervisor.init(children, strategy: :one_for_one)
    end
  end

  ################################
  # Private API
  ################################

  defp consumer_init(consumer, opts) do
    if Code.ensure_loaded?(consumer) and function_exported?(consumer, :init, 1) do
      consumer.init(opts)
    else
      {:ok, opts}
    end
  end

  defp handler_name(module) do
    Module.concat(module, Handler)
  end
end
