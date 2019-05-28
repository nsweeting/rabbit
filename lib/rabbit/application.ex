defmodule Rabbit.Application do
  use Application

  def start(_type, _args) do
    children = [
      Rabbit.WorkerSupervisor
    ]

    opts = [strategy: :one_for_one, name: Rabbit.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
