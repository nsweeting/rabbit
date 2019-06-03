defmodule Rabbit.Serializers.ETF do
  @moduledoc false

  @behaviour Rabbit.Serializer

  @doc false
  @impl Rabbit.Serializer
  def encode(data) do
    data = data |> :erlang.term_to_binary() |> Base.encode64(padding: false)
    {:ok, data}
  rescue
    error -> {:error, error}
  end

  @doc false
  @impl Rabbit.Serializer
  def decode(data) do
    data = data |> Base.decode64!(padding: false) |> :erlang.binary_to_term()
    {:ok, data}
  rescue
    error -> {:error, error}
  end
end
