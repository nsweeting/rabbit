defmodule Rabbit.SerializerError do
  defexception [:message]

  def exception(error), do: error
end
