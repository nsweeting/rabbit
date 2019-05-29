{:ok, conn} = Rabbit.Connection.start_link()
{:ok, prod} = Rabbit.Producer.start_link(conn, pool_size: 10)

Benchee.run(%{
  "publish json" => fn ->
    Rabbit.Producer.publish(
      prod,
      "",
      "test1",
      %{foo: "bar", bar: "baz"},
      content_type: "application/json"
    )
  end,
  "publish etf" => fn ->
    Rabbit.Producer.publish(
      prod,
      "",
      "test2",
      %{foo: "bar", bar: "baz"},
      content_type: "application/erlang-binary"
    )
  end
})
