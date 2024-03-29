defmodule Rabbit.Producer.Pool do
  @moduledoc false

  alias Rabbit.Producer.Server

  @opts_schema KeywordValidator.schema!(
                 pool_size: [is: :integer, default: 1, required: true],
                 max_overflow: [is: :integer, default: 0, required: true],
                 strategy: [is: :atom, default: :lifo, required: true]
               )

  defmodule Worker do
    @moduledoc false

    @doc false
    def start_link(opts) when is_list(opts) do
      {module, opts} = Keyword.pop(opts, :module)
      Server.start_link(module, opts)
    end
  end

  ################################
  # Public API
  ################################

  @doc false
  def start_link(module, opts \\ [], server_opts \\ []) do
    worker_opts = get_worker_opts(module, opts)

    with {:ok, opts} <- module.init(:producer_pool, opts),
         {:ok, opts} <- validate_opts(opts) do
      pool_opts = get_pool_opts(opts, server_opts)
      :poolboy.start_link(pool_opts, worker_opts)
    end
  end

  ################################
  # Private API
  ################################

  defp validate_opts(opts) do
    KeywordValidator.validate(opts, @opts_schema, strict: false)
  end

  defp get_pool_opts(opts, server_opts) do
    [
      worker_module: Worker,
      size: Keyword.get(opts, :pool_size, 1),
      max_overflow: Keyword.get(opts, :max_overflow, 0),
      strategy: Keyword.get(opts, :strategy, :lifo)
    ]
    |> with_pool_name(server_opts)
  end

  defp with_pool_name(pool_opts, server_opts) do
    name = Keyword.get(server_opts, :name)

    if name do
      pool_opts ++ [{:name, {:local, name}}]
    else
      pool_opts
    end
  end

  defp get_worker_opts(module, opts) do
    opts = Keyword.drop(opts, [:pool_size, :max_overflow, :strategy])
    Keyword.put(opts, :module, module)
  end
end
