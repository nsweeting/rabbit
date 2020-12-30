defmodule Rabbit.Broker.Supervisor do
  @moduledoc false

  use Supervisor

  alias Rabbit.Broker

  ################################
  # Public API
  ################################

  @doc false
  def start_link(module, opts \\ [], server_opts \\ []) do
    Supervisor.start_link(__MODULE__, {module, opts}, server_opts)
  end

  ################################
  # Supervisor Callbacks
  ################################

  @doc false
  @impl Supervisor
  def init(args) do
    children =
      []
      |> with_connection(args)
      |> with_toplogy(args)
      |> with_producer(args)
      |> with_consumers(args)

    Supervisor.init(children, strategy: :one_for_one)
  end

  ################################
  # Private API
  ################################

  defp with_connection(children, {module, opts}) do
    name = Broker.connection(module)
    opts = Keyword.get(opts, :connection, [])
    spec = build_spec(Rabbit.Connection.Pool, name, module, opts)

    children ++ [spec]
  end

  defp with_toplogy(children, {module, opts}) do
    conn = Broker.connection(module)
    name = Broker.topology(module)
    # Temporary support for old initializer keyword
    opts = Keyword.get(opts, :initializer) || Keyword.get(opts, :topology, [])
    opts = Keyword.put(opts, :connection, conn)
    spec = build_spec(Rabbit.Topology.Server, name, module, opts)

    children ++ [spec]
  end

  defp with_producer(children, {module, opts}) do
    conn = Broker.connection(module)
    name = Broker.producer(module)
    opts = Keyword.get(opts, :producer, [])
    opts = Keyword.put(opts, :connection, conn)
    spec = build_spec(Rabbit.Producer.Pool, name, module, opts)

    children ++ [spec]
  end

  defp with_consumers(children, {module, opts}) do
    conn = Broker.connection(module)
    name = Broker.consumers(module)
    opts = Keyword.get(opts, :consumers, [])
    opts = Enum.map(opts, &Keyword.put(&1, :connection, conn))
    spec = build_spec(Rabbit.Consumer.Supervisor, name, module, opts)

    children ++ [spec]
  end

  defp build_spec(server, name, module, opts) do
    %{
      id: name,
      start: {server, :start_link, [module, opts, [name: name]]}
    }
  end
end
