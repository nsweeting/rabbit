defmodule Connection do
  use Rabbit.Connection
end

defmodule Producer do
  use Rabbit.Producer
end

Connection.start_link()
Producer.start_link(connection: Connection)

Benchee.run(%{
  "publish json" => fn ->
    Producer.publish("", "test1", %{foo: "bar", bar: "baz"}, content_type: "application/json")
  end,
  "publish etf" => fn ->
    Producer.publish("", "test2", %{foo: "bar", bar: "baz"},
      content_type: "application/erlang-binary"
    )
  end
})
