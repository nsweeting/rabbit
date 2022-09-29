defmodule Rabbit.Utilities do
  @moduledoc false

  @doc false
  @spec process_name(pid | nil) :: pid() | atom()
  def process_name(pid \\ nil) do
    (pid || self())
    |> Process.info()
    |> Keyword.get(:registered_name, self())
  end

  @doc false
  @spec validate_opts(keyword(), KeywordValidator.schema(), keyword()) ::
          {:ok, keyword()} | {:error, keyword()}
  def validate_opts(keyword, schema, opts \\ []) do
    case KeywordValidator.validate(keyword, schema, opts) do
      {:ok, _} = result -> result
      {:error, reason} -> {:stop, reason}
    end
  end
end
