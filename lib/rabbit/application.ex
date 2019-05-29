defmodule Rabbit.Application do
  use Application

  @impl Application
  def start(_type, _args) do
    children = [
      Rabbit.Config,
      Rabbit.WorkerSupervisor
    ]

    opts = [strategy: :one_for_one, name: Rabbit.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
