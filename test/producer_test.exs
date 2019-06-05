defmodule Rabbit.ProducerTest do
  use ExUnit.Case

  alias Rabbit.{Connection, Producer}

  describe "start_link/3" do
    test "starts producer" do
      assert {:ok, connection} = Connection.start_link()
      assert {:ok, _producer} = Producer.start_link(connection)
    end

    test "starts producer with pool_size" do
      assert {:ok, connection} = Connection.start_link()
      assert {:ok, producer} = Producer.start_link(connection, pool_size: 2)
      assert [_, _] = GenServer.call(producer, :get_avail_workers)
      assert {:ok, producer} = Producer.start_link(connection, pool_size: 3)
      assert [_, _, _] = GenServer.call(producer, :get_avail_workers)
    end
  end

  describe "stop/1" do
    test "stops producer" do
      assert {:ok, connection} = Connection.start_link()
      assert {:ok, producer} = Producer.start_link(connection)
      assert :ok = Producer.stop(producer)
      refute Process.alive?(producer)
    end

    test "disconnects the amqp channel" do
      assert {:ok, connection} = Connection.start_link()
      assert {:ok, producer} = Producer.start_link(connection)

      await_publishing(producer)

      [worker] = GenServer.call(producer, :get_avail_workers)
      state = GenServer.call(worker, :state)

      assert Process.alive?(state.channel.pid)
      assert :ok = Producer.stop(producer)

      refute Process.alive?(state.channel.pid)
    end
  end

  describe "publish/6" do
    test "publishes payload to queue" do
      {:ok, amqp_conn} = AMQP.Connection.open()
      {:ok, amqp_chan} = AMQP.Channel.open(amqp_conn)
      AMQP.Queue.declare(amqp_chan, "foo")
      AMQP.Queue.purge(amqp_chan, "foo")

      assert {:ok, connection} = Connection.start_link()
      assert {:ok, producer} = Producer.start_link(connection)

      await_publishing(producer)

      assert :ok = Producer.publish(producer, "", "foo", "bar")

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

    assert {:ok, connection} = Connection.start_link()
    assert {:ok, producer} = Producer.start_link(connection)

    state = GenServer.call(connection, :state)
    AMQP.Connection.close(state.connection)
    :timer.sleep(50)

    assert :ok = Producer.publish(producer, "", "producer", "bar")
  end

  test "creating producer modules" do
    defmodule ProOne do
      use Rabbit.Producer
    end

    {:ok, amqp_conn} = AMQP.Connection.open()
    {:ok, amqp_chan} = AMQP.Channel.open(amqp_conn)
    AMQP.Queue.declare(amqp_chan, "producer")
    AMQP.Queue.purge(amqp_chan, "producer")

    assert {:ok, connection} = Connection.start_link()
    assert {:ok, producer} = ProOne.start_link(connection)

    await_publishing(producer)

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

    assert {:ok, connection} = Connection.start_link()
    assert {:ok, producer} = ProTwo.start_link(connection)
    assert_receive :init_callback
  end

  def await_publishing(producer) do
    producer
    |> GenServer.call(:get_avail_workers)
    |> List.first()
    |> GenServer.call(:state)
    |> case do
      %{channel: nil} ->
        :timer.sleep(10)
        await_publishing(producer)

      _ ->
        :ok
    end
  end
end
