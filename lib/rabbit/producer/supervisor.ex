defmodule Rabbit.Producer.Supervisor do
  @moduledoc false

  use Supervisor

  import Rabbit.Utilities

  @opts %{
    name: [type: [:atom, :tuple], required: false],
    pool_size: [type: :integer, default: 1],
    max_overflow: [type: :integer, default: 0],
    serializers: [type: :map, default: Rabbit.Serializer.defaults()],
    publish_opts: [type: :list, default: []]
  }

  ################################
  # Public API
  ################################

  @doc false
  def start_link(connection, opts \\ []) do
    Supervisor.start_link(__MODULE__, {connection, opts})
  end

  ################################
  # Supervisor Callbacks
  ################################

  @doc false
  @impl Supervisor
  def init({connection, opts}) do
    with {:ok, opts} <- producer_init(opts) do
      opts = KeywordValidator.validate!(opts, @opts)

      children = [
        {Rabbit.Producer.Pool, [connection, opts]}
      ]

      Supervisor.init(children, strategy: :one_for_one)
    end
  end

  ################################
  # Private API
  ################################

  defp producer_init(opts) do
    {module, opts} = Keyword.pop(opts, :module)

    if callback_exported?(module, :init, 1) do
      module.init(opts)
    else
      {:ok, opts}
    end
  end
end
