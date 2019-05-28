defmodule Rabbit.Producer.Pool do
  @moduledoc false

  ################################
  # Public API
  ################################

  @doc false
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, opts}
    }
  end

  @doc false
  def start_link(connection, opts \\ []) do
    pool_opts = get_pool_opts(opts)
    worker_opts = get_worker_opts(connection, opts)
    :poolboy.start_link(pool_opts, worker_opts)
  end

  @doc false
  def publish(producer, exchange, routing_key, payload, opts \\ [], timeout \\ 5_000) do
    :poolboy.transaction(
      producer,
      &Rabbit.Producer.Server.publish(&1, exchange, routing_key, payload, opts, timeout)
    )
  end

  ################################
  # Private API
  ################################

  defp get_pool_opts(opts) do
    [
      {:worker_module, Rabbit.Producer.Server},
      {:size, Keyword.get(opts, :pool_size, 1)},
      {:max_overflow, Keyword.get(opts, :max_overflow, 0)}
    ]
    |> with_pool_name(opts)
  end

  defp with_pool_name(pool_opts, opts) do
    name = Keyword.get(opts, :name)

    if name do
      pool_opts ++ [{:name, {:local, name}}]
    else
      pool_opts
    end
  end

  defp get_worker_opts(connection, opts) do
    opts = Keyword.take(opts, [:name, :serializers, :publish_opts])
    Keyword.put(opts, :connection, connection)
  end
end
