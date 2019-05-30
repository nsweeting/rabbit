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
      try do
        Jason.decode(data)
      rescue
        exception -> {:error, exception}
      end
    end
  end
end
