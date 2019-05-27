defmodule Rabbit.Consumer.WorkerSupervisor do
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
  def start_link(name) do
    DynamicSupervisor.start_link(__MODULE__, [], name: name)
  end

  @doc false
  def start_child(worker, message, opts \\ []) do
    child = {Rabbit.Consumer.Worker, [message, opts]}
    DynamicSupervisor.start_child(worker, child)
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
