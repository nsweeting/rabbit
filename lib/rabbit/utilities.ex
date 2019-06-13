defmodule Rabbit.Utilities do
  @moduledoc false

  @doc false
  @spec process_name(pid | nil) :: pid() | atom()
  def process_name(pid \\ nil) do
    (pid || self())
    |> Process.info()
    |> Keyword.get(:registered_name, self())
  end
end
