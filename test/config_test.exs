defmodule Rabbit.ConfigTest do
  use ExUnit.Case

  alias Rabbit.Config

  describe "put/2" do
    test "will return an error if key is invalid" do
      assert {:error, :invalid_key} = Config.put(:foo, :bar)
    end

    test "will return an error if worker_pool_size is less than 1" do
      assert {:error, ["must be greater than 0"]} = Config.put(:worker_pool_size, 0)
    end
  end
end
