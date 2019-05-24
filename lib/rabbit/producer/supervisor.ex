defmodule Rabbit.Producer.Supervisor do
  @moduledoc false

  use Supervisor

  @opts %{
    pool_size: [type: :integer, default: 1],
    max_overflow: [type: :integer, default: 0],
    serializers: [type: :map, default: Rabbit.Serializer.defaults()],
    publish_opts: [type: :list, default: []]
  }

  ################################
  # Public API
  ################################

  @doc false
  def start_link(producer, connection, opts \\ []) do
    Supervisor.start_link(__MODULE__, {producer, connection, opts})
  end

  ################################
  # Supervisor Callbacks
  ################################

  @doc false
  @impl Supervisor
  def init({producer, connection, opts}) do
    with {:ok, opts} <- producer_init(producer, opts) do
      opts = KeywordValidator.validate!(opts, @opts)

      children = [
        {Rabbit.Producer.Pool, [producer, connection, opts]}
      ]

      Supervisor.init(children, strategy: :one_for_one)
    end
  end

  ################################
  # Private API
  ################################

  defp producer_init(producer, opts) do
    if Code.ensure_loaded?(producer) and function_exported?(producer, :init, 1) do
      producer.init(opts)
    else
      {:ok, opts}
    end
  end
end
