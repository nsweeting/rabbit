if Code.ensure_loaded?(Jason) do
  defmodule Rabbit.Serializers.JSON do
    @moduledoc false

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
    rescue
      exception -> {:error, exception}
    end
  end
end
