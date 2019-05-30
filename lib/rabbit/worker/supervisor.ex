defmodule Rabbit.Worker.Supervisor do
  @moduledoc false

  use Supervisor

  ################################
  # Public API
  ################################

  @spec start_link(any) :: Supervisor.on_start()
  def start_link(_) do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  ################################
  # Supervisor Callbacks
  ################################

  @doc false
  @impl Supervisor
  def init(:ok) do
    children = build_workers()

    Supervisor.init(children, strategy: :one_for_one)
  end

  ################################
  # Private API
  ################################

  defp build_workers do
    Enum.reduce(0..Rabbit.Worker.pool_total(), [], fn number, children ->
      name = Rabbit.Worker.get_name(number)
      child = Supervisor.child_spec({Rabbit.Worker, [[name: name]]}, id: name)
      children ++ [child]
    end)
  end
end
