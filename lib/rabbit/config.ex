defmodule Rabbit.Config do
  @moduledoc false

  ################################
  # Public API
  ################################

  @spec get(atom()) :: {:ok, any()} | :error
  def get(:serializers) do
    case Application.get_env(:rabbit, :serializers) do
      nil ->
        {:ok, Rabbit.Serializer.defaults()}

      serializers when is_map(serializers) ->
        {:ok, serializers}

      _ ->
        :error
    end
  end

  def get(_), do: :error
end
