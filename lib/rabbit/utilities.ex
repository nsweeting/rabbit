defmodule Rabbit.Utilities do
  @moduledoc false

  @doc false
  @spec callback_exported?(module(), atom(), non_neg_integer()) :: boolean()
  def callback_exported?(module, function, arity) do
    Code.ensure_loaded?(module) and function_exported?(module, function, arity)
  end

  @doc false
  @spec process_name(pid | nil) :: pid() | atom()
  def process_name(pid \\ nil) do
    (pid || self())
    |> Process.info()
    |> Keyword.get(:registered_name, self())
  end
end
