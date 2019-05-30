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
    pool_total = pool_total()
    worker = message |> :erlang.phash2(pool_total) |> get_name()
    child = {Rabbit.Worker.Executer, [message, opts]}
    DynamicSupervisor.start_child(worker, child)
  end

  @doc false
  def get_name(number) do
    Module.concat(Rabbit.Worker, ".#{number}")
  end

  @spec pool_total :: number()
  def pool_total do
    {:ok, pool_size} = Rabbit.Config.get(:worker_pool_size)
    pool_size - 1
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
