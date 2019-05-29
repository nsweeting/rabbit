defmodule Rabbit.Worker.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link(_) do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    children = build_workers()

    Supervisor.init(children, strategy: :one_for_one)
  end

  def worker_total do
    {:ok, worker_count} = Rabbit.Config.get(:worker_count)
    worker_count - 1
  end

  defp build_workers do
    Enum.reduce(0..worker_total(), [], fn number, children ->
      name = Rabbit.Worker.get_name(number)
      child = Supervisor.child_spec({Rabbit.Worker, [[name: name]]}, id: name)
      children ++ [child]
    end)
  end
end
