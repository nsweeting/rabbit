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
  @spec validate_opts(keyword(), map()) :: {:ok, keyword()} | {:error, keyword()}
  def validate_opts(opts, schema) do
    case KeywordValidator.validate(opts, schema) do
      {:ok, _} = result -> result
      {:error, reason} -> {:stop, reason}
    end
  end
end
