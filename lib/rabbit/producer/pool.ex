defmodule Rabbit.Producer.Pool do
  @moduledoc false

  ################################
  # Public API
  ################################

  @worker_opts [
    :connection,
    :publish_opts,
    :async_connect
  ]

  @doc false
  def start_link(module, opts \\ [], server_opts \\ []) do
    pool_opts = get_pool_opts(opts, server_opts)
    worker_opts = get_worker_opts(module, opts)
    :poolboy.start_link(pool_opts, worker_opts)
  end

  ################################
  # Private API
  ################################

  defp get_pool_opts(opts, server_opts) do
    [
      {:worker_module, Rabbit.Producer.Server},
      {:size, Keyword.get(opts, :pool_size, 1)},
      {:max_overflow, Keyword.get(opts, :max_overflow, 0)}
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
    opts = Keyword.take(opts, @worker_opts)
    Keyword.put(opts, :module, module)
  end
end
