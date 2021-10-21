defmodule Rabbit.Consumer.Worker do
  @moduledoc false

  use DynamicSupervisor

  ################################
  # Public API
  ################################

  @doc false
  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, [], opts)
  end

  @doc false
  def start_child(worker, message, opts \\ []) do
    child = {Rabbit.Consumer.Executer, [message, opts]}
    DynamicSupervisor.start_child(worker, child)
  end

  @doc false
  def stop(worker) do
    DynamicSupervisor.stop(worker)
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
