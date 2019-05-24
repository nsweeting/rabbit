if Code.ensure_loaded?(Jason) do
  defmodule Rabbit.Serializers.JSON do
    @behaviour Rabbit.Serializer

    @doc false
    @impl Rabbit.Serializer
    def encode(data) do
      Jason.encode(data)
    end

    @doc false
    @impl Rabbit.Serializer
    def decode(data) do
      Jason.decode(data)
    end
  end
end
