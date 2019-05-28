defmodule Rabbit.WorkerSupervisor do
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
  def start_link do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc false
  def start_child(message, opts \\ []) do
    child = {Rabbit.Worker, [message, opts]}
    DynamicSupervisor.start_child(__MODULE__, child)
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
