defmodule Rabbit.Consumer.Supervisor do
  @moduledoc false

  use Supervisor

  ################################
  # Public API
  ################################

  @doc false
  def start_link(connection, module, server_opts \\ []) do
    Supervisor.start_link(__MODULE__, {connection, module}, server_opts)
  end

  ################################
  # Supervisor Callbacks
  ################################

  @doc false
  @impl Supervisor
  def init({connection, module}) do
    consumers = module.consumers()
    children = build_children(connection, module, consumers, [])
    Supervisor.init(children, strategy: :one_for_one)
  end

  ################################
  # Private API
  ################################

  defp build_children(_connection, _module, [], children) do
    children
  end

  defp build_children(connection, module, [consumer | consumers], children) do
    id = Enum.count(children) |> to_string() |> String.to_atom()
    opts = Keyword.put(consumer, :module, module)
    spec = {Rabbit.Consumer, [connection, opts]}
    children = children ++ [Supervisor.child_spec(spec, id: id)]
    build_children(connection, module, consumers, children)
  end
end
