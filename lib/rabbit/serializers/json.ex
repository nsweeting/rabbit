if Code.ensure_loaded?(Jason) do
  defmodule Rabbit.Serializers.JSON do
    @moduledoc false

    @behaviour Rabbit.Serializer

    @doc false
    @impl Rabbit.Serializer
    def encode(data) do
      Jason.encode(data)
    rescue
      error -> {:error, error}
    end

    @doc false
    @impl Rabbit.Serializer
    def decode(data) do
      Jason.decode(data)
    rescue
      error -> {:error, error}
    end
  end
end
