defmodule Rabbit.ProducerTest do
  use ExUnit.Case

  alias Rabbit.{Connection, Producer}

  describe "start_link/1" do
    test "starts producer" do
      assert {:ok, conn} = Connection.start_link()
      assert {:ok, pro} = Producer.start_link(conn)
    end

    test "starts producer with pool_size" do
      assert {:ok, conn} = Connection.start_link()
      assert {:ok, pro} = Producer.start_link(conn, pool_size: 2)
      assert [_, _] = GenServer.call(pro, :get_avail_workers)
      assert {:ok, pro} = Producer.start_link(conn, pool_size: 3)
      assert [_, _, _] = GenServer.call(pro, :get_avail_workers)
    end
  end

  describe "stop/2" do
    test "stops producer" do
      assert {:ok, conn} = Connection.start_link()
      assert {:ok, pro} = Producer.start_link(conn)
      assert :ok = Producer.stop(pro)
      refute Process.alive?(pro)
    end
  end
end
