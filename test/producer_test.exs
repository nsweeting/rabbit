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

    test "disconnects the amqp channel" do
      assert {:ok, conn} = Connection.start_link()
      assert {:ok, pro} = Producer.start_link(conn)

      :timer.sleep(50)
      [worker] = GenServer.call(pro, :get_avail_workers)
      state = GenServer.call(worker, :state)

      assert Process.alive?(state.channel.pid)
      assert :ok = Producer.stop(pro)

      refute Process.alive?(state.channel.pid)
    end
  end

  describe "publish/6" do
    test "publishes payload to queue" do
      {:ok, amqp_conn} = AMQP.Connection.open()
      {:ok, amqp_chan} = AMQP.Channel.open(amqp_conn)
      AMQP.Queue.declare(amqp_chan, "foo")
      AMQP.Queue.purge(amqp_chan, "foo")

      assert {:ok, conn} = Connection.start_link()
      assert {:ok, pro} = Producer.start_link(conn)

      :timer.sleep(50)

      assert :ok = Producer.publish(pro, "", "foo", "bar")

      :timer.sleep(50)

      assert 1 = AMQP.Queue.message_count(amqp_chan, "foo")
    end
  end
end
