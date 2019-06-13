defmodule Rabbit.Consumer.Supervisor do
  @moduledoc false

  use Supervisor

  ################################
  # Public API
  ################################

  @doc false
  def start_link(module, consumers \\ [], server_opts \\ []) do
    Supervisor.start_link(__MODULE__, {module, consumers}, server_opts)
  end

  ################################
  # Supervisor Callbacks
  ################################

  @doc false
  @impl Supervisor
  def init({module, consumers}) do
    with {:ok, consumers} <- module.init(:consumer_supervisor, consumers) do
      children = build_children(module, consumers, [])
      Supervisor.init(children, strategy: :one_for_one)
    end
  end

  ################################
  # Private API
  ################################

  defp build_children(_module, [], children) do
    children
  end

  defp build_children(module, [consumer | consumers], children) do
    id = children |> Enum.count() |> to_string() |> String.to_atom()
    spec = %{id: id, start: {Rabbit.Consumer, :start_link, [module, consumer]}}
    children = children ++ [spec]
    build_children(module, consumers, children)
  end
end
