defmodule Rabbit.Application do
  @moduledoc false

  use Application

  @doc false
  @impl Application
  def start(_type, _args) do
    children = [
      Rabbit.Config
    ]

    opts = [strategy: :one_for_one, name: Rabbit.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
