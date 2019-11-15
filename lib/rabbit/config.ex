defmodule Rabbit.Config do
  @moduledoc false

  use GenServer

  @table __MODULE__

  ################################
  # Public API
  ################################

  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec get(atom()) :: :error | {:ok, any}
  def get(key) do
    case :ets.lookup(@table, key) do
      [{_, val} | _] ->
        {:ok, val}

      _ ->
        :error
    end
  end

  @spec put(atom(), any()) :: :ok
  def put(key, val) do
    GenServer.call(__MODULE__, {:put, key, val})
  end

  ################################
  # GenServer Callbacks
  ################################

  @doc false
  @impl GenServer
  def init(opts) do
    opts
    |> init_opts()
    |> init_table()

    {:ok, :ok}
  end

  @doc false
  @impl GenServer
  def handle_call({:put, key, val}, _from, state) do
    result = do_put(key, val)
    {:reply, result, state}
  end

  ################################
  # Private API
  ################################

  defp init_opts(opts) do
    :rabbit
    |> Application.get_all_env()
    |> Keyword.merge(opts)
    |> KeywordValidator.validate!(opts_schema())
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
      worker_pool_size: [
        type: :integer,
        default: System.schedulers_online(),
        required: true,
        custom: [&validate_key(&1, &2)]
      ],
      serializers: [
        type: :map,
        default: Rabbit.Serializer.defaults(),
        required: true
      ]
    }
  end

  defp validate_key(:worker_pool_size, size) when size < 1, do: ["must be greater than 0"]
  defp validate_key(_key, _val), do: []

  defp do_put(opts) when is_list(opts) do
    for {key, val} <- opts, do: do_put(key, val)
  end

  defp do_put(key, val) do
    with true <- Map.has_key?(opts_schema(), key),
         [] <- validate_key(key, val) do
      :ets.insert(@table, {key, val})
      :ok
    else
      false -> {:error, :invalid_key}
      errors -> {:error, errors}
    end
  end
end
