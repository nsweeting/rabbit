defmodule Rabbit.Config do
  use GenServer

  @table __MODULE__

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get(key) do
    case :ets.lookup(@table, key) do
      [{_, val} | _] ->
        {:ok, val}

      _ ->
        :error
    end
  end

  def put(key, val) do
    GenServer.call(__MODULE__, {:put, key, val})
  end

  def init(opts) do
    opts
    |> init_opts()
    |> init_table()

    {:ok, :ok}
  end

  def handle_call({:put, key, val}, _from, state) do
    result = do_put(key, val)
    {:reply, result, state}
  end

  defp init_opts(opts) do
    KeywordValidator.validate!(opts, %{
      worker_count: [type: :integer, default: System.schedulers_online(), required: true]
    })
  end

  defp init_table(opts) do
    if :ets.info(@table) == :undefined do
      :ets.new(@table, [:named_table, :protected, read_concurrency: true])
    end

    do_put(opts)

    :ok
  end

  defp opts_schema do
    %{
      worker_count: [type: :integer, default: System.schedulers_online(), required: true]
    }
  end

  defp do_put(opts) when is_list(opts) do
    for {key, val} <- opts, do: do_put(key, val)
  end

  defp do_put(key, val) do
    if Map.has_key?(opts_schema(), key) do
      :ets.insert(@table, {key, val})
      :ok
    else
      {:error, :invalid_key}
    end
  end
end
