defmodule Rabbit.Serializers.ETF do
  @behaviour Rabbit.Serializer

  @doc false
  @impl Rabbit.Serializer
  def encode(data) do
    data = data |> :erlang.term_to_binary() |> Base.encode64(padding: false)
    {:ok, data}
  rescue
    _ -> {:error, :etf_encoding}
  end

  @doc false
  @impl Rabbit.Serializer
  def decode(data) do
    data = data |> Base.decode64!(padding: false) |> :erlang.binary_to_term()
    {:ok, data}
  rescue
    _ -> {:error, :etf_decoding}
  end
end
