defmodule Rabbit.SerializerError do
  @moduledoc false
  defexception [:message]
end

defmodule Rabbit.Serializer do
  @moduledoc """
  A behaviour to implement serializers.

  To create a serializer, you just need to implement the `c:encode/1` and `c:decode/1`
  callbacks,

  ## Example

        defmodule MySerializer do
          @behaviour Rabbit.Serializer

          @impl true
          def encode(data) do
            # Create a binary from data
          end

          @impl true
          def decode(binary) do
            # Create data from a binary
          end
        end

  ## Default Serializers

  By default, Rabbit comes with serializers for the following content types:

  * `"application/erlang"`
  * `"application/json"` - requires the `Jason` library to be added.

  You can modify the default serializers through application config:

        config :rabbit,
          serializers: %{
            "application/custom-type" => MySerializer
          }

  """

  @type t :: module()

  @doc """
  Callback invoked to encode the given data to a binary.
  """
  @callback encode(any()) :: {:ok, binary()} | {:error, Exception.t()}

  @doc """
  Callback invoked to decode the given binary to data.
  """
  @callback decode(binary()) :: {:ok, any()} | {:error, Exception.t()}

  @defaults %{
    "application/json" => Rabbit.Serializers.JSON,
    "application/erlang-binary" => Rabbit.Serializers.ETF
  }

  @doc false
  @spec encode(Rabbit.Serializer.t(), any()) :: {:ok, any()} | {:error, Exception.t()}
  def encode(serializer, data) do
    do_serialize(serializer, :encode, data)
  end

  @doc false
  @spec encode!(Rabbit.Serializer.t(), any()) :: any
  def encode!(serializer, data) do
    case encode(serializer, data) do
      {:ok, data} -> data
      {:error, error} -> raise Rabbit.SerializerError, Exception.message(error)
    end
  end

  @doc false
  @spec decode(Rabbit.Serializer.t(), any()) :: {:ok, any()} | {:error, Exception.t()}
  def decode(serializer, data) do
    do_serialize(serializer, :decode, data)
  end

  @doc false
  @spec decode!(Rabbit.Serializer.t(), any()) :: any
  def decode!(serializer, data) do
    case decode(serializer, data) do
      {:ok, data} -> data
      {:error, error} -> raise Rabbit.SerializerError, Exception.message(error)
    end
  end

  @doc false
  @spec defaults() :: map()
  def defaults do
    @defaults
  end

  defp do_serialize(serializer, fun, data) do
    apply(serializer, fun, [data])
  end
end
