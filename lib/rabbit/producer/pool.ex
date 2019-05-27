defmodule Rabbit.Producer.Pool do
  @moduledoc false

  ################################
  # Public API
  ################################

  @doc false
  def child_spec(args) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, args}
    }
  end

  @doc false
  def start_link(producer, connection, opts \\ []) do
    {pool_opts, opts} = Keyword.split(opts, [:pool_size, :max_overflow])
    opts = Keyword.merge(opts, producer: producer, connection: connection)
    :poolboy.start_link(config(producer, pool_opts), opts)
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

  defp config(name, opts) do
    [
      {:name, {:local, name}},
      {:worker_module, Rabbit.Producer.Server},
      {:size, opts[:pool_size]},
      {:max_overflow, opts[:max_overflow]}
    ]
  end
end
