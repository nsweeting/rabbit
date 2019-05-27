Rabbit.Connection.start_link(:conn)
Rabbit.Producer.start_link(:producer, :conn)

Benchee.run(%{
  "publish json" => fn ->
    Rabbit.Producer.publish(
      :producer,
      "",
      "test1",
      %{foo: "bar", bar: "baz"},
      content_type: "application/json"
    )
  end,
  "publish etf" => fn ->
    Rabbit.Producer.publish(
      :producer,
      "",
      "test2",
      %{foo: "bar", bar: "baz"},
      content_type: "application/erlang-binary"
    )
  end
})
