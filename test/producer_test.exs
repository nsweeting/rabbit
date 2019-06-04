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
      assert :ok = Producer.publish(pro, "", "foo", "bar")

      :timer.sleep(50)

      assert 1 = AMQP.Queue.message_count(amqp_chan, "foo")
    end
  end

  @tag capture_log: true
  test "will reconnect when connection stops" do
    {:ok, amqp_conn} = AMQP.Connection.open()
    {:ok, amqp_chan} = AMQP.Channel.open(amqp_conn)
    AMQP.Queue.declare(amqp_chan, "producer")
    AMQP.Queue.purge(amqp_chan, "producer")

    assert {:ok, conn} = Connection.start_link()
    assert {:ok, pro} = Producer.start_link(conn)

    state = GenServer.call(conn, :state)
    AMQP.Connection.close(state.connection)
    :timer.sleep(50)

    assert :ok = Producer.publish(pro, "", "producer", "bar")
  end

  test "creating producer modules" do
    defmodule ProOne do
      use Rabbit.Producer
    end

    {:ok, amqp_conn} = AMQP.Connection.open()
    {:ok, amqp_chan} = AMQP.Channel.open(amqp_conn)
    AMQP.Queue.declare(amqp_chan, "producer")
    AMQP.Queue.purge(amqp_chan, "producer")

    assert {:ok, conn} = Connection.start_link()
    assert {:ok, pro} = ProOne.start_link(conn)
    assert :ok = ProOne.publish("", "producer", "bar")
  end

  test "producer modules use init callback" do
    Process.register(self(), :pro_two)

    defmodule ProTwo do
      use Rabbit.Producer

      def init(opts) do
        send(:pro_two, :init_callback)
        {:ok, opts}
      end
    end

    assert {:ok, conn} = Connection.start_link()
    assert {:ok, pro} = ProTwo.start_link(conn)
    assert_receive :init_callback
  end
end
