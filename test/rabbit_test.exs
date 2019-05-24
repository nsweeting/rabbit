defmodule RabbitTest do
  use ExUnit.Case
  doctest Rabbit

  test "greets the world" do
    assert Rabbit.hello() == :world
  end
end
