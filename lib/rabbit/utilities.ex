defmodule Rabbit.Utilities do
  @moduledoc false

  @doc false
  @spec callback_exported?(module(), atom(), non_neg_integer()) :: boolean()
  def callback_exported?(module, function, arity) do
    Code.ensure_loaded?(module) and function_exported?(module, function, arity)
  end
end
