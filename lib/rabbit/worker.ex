defmodule Rabbit.Worker do
  @moduledoc false

  use DynamicSupervisor

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
  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, [], opts)
  end

  @doc false
  def start_child(message, opts \\ []) do
    worker_total = Rabbit.WorkerSupervisor.worker_total()
    number = :erlang.phash2(message, worker_total)
    child = {Rabbit.Runner, [message, opts]}
    DynamicSupervisor.start_child(get_name(number), child)
  end

  def get_name(number) do
    Module.concat(Rabbit.Worker, ".#{number}")
  end

  ################################
  # DynamicSupervisor Callbacks
  ################################

  @doc false
  @impl DynamicSupervisor
  def init(_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
