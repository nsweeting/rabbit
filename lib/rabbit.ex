defmodule Rabbit do
end

defmodule Connection do
  use Rabbit.Connection
end

defmodule Consumer do
  use Rabbit.Consumer

  def init(_) do
    {:ok, connection: :foo, queue: "test", durable: true}
  end

  def handle_message(_) do
  end

  def handle_error(_) do
  end
end
