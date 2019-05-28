defmodule Rabbit.Utilities do
  @doc false
  @spec callback_exported?(module(), atom(), non_neg_integer()) :: boolean()
  def callback_exported?(module, function, arity) do
    Code.ensure_loaded?(module) and function_exported?(module, function, arity)
  end

  @spec safe_call(module(), atom(), list()) :: any() | {:error, tuple()}
  def safe_call(module, function, args) do
    try do
      apply(module, function, args)
    catch
      msg, reason -> {:error, {msg, reason}}
    end
  end
end
