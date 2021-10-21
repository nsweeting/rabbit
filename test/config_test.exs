defmodule Rabbit.ConfigTest do
  use ExUnit.Case

  alias Rabbit.Config

  describe "get/1" do
    test "will return an error if key is invalid" do
      assert Config.get(:foo) == :error
    end

    test "will return serializers" do
      assert Config.get(:serializers) == {:ok, Rabbit.Serializer.defaults()}
    end
  end
end
