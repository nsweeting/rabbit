defmodule Rabbit.Serializer do
  @type t :: module()
  @type error :: {:error, binary()}

  @callback encode(any()) :: {:ok, any()} | error()

  @callback decode(any()) :: {:ok, any()} | error()

  @defaults %{
    "application/json" => Rabbit.Serializers.JSON,
    "application/erlang-binary" => Rabbit.Serializers.ETF
  }

  @spec encode(Rabbit.Serializer.t(), any()) :: {:ok, any()} | error()
  def encode(serializer, data) do
    do_serialize(serializer, :encode, data)
  end

  @spec encode!(Rabbit.Serializer.t(), any()) :: {:ok, any()} | error()
  def encode!(serializer, data) do
    case encode(serializer, data) do
      {:ok, data} -> data
      {:error, error} -> raise Rabbit.SerializerError, error
    end
  end

  @spec decode(Rabbit.Serializer.t(), any()) :: {:ok, any()} | error()
  def decode(serializer, data) do
    do_serialize(serializer, :decode, data)
  end

  @spec decode!(Rabbit.Serializer.t(), any()) :: {:ok, any()} | error()
  def decode!(serializer, data) do
    case decode(serializer, data) do
      {:ok, data} -> data
      {:error, error} -> raise Rabbit.SerializerError, error
    end
  end

  @spec defaults() :: map()
  def defaults do
    @defaults
  end

  defp do_serialize(serializer, fun, data) do
    apply(serializer, fun, [data])
  end
end
