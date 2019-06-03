defmodule Rabbit.ConsumerTest do
  use ExUnit.Case

  alias Rabbit.{Consumer, Connection, Producer}

  defmodule ConOne do
    use Rabbit.Consumer

    def after_connect(chan, queue) do
      AMQP.Queue.declare(chan, queue, auto_delete: true)
      AMQP.Queue.purge(chan, queue)

      :ok
    end

    def handle_message(msg) do
      decoded_payload = Base.decode64!(msg.payload)
      {pid, signature} = :erlang.binary_to_term(decoded_payload)
      send(pid, {:handle_message, signature})
      {:ack, msg}
    end

    def handle_error(msg) do
      {:nack, msg}
    end
  end

  setup do
    {:ok, conn} = Connection.start_link()
    {:ok, pro} = Producer.start_link(conn, async_connect: false)
    %{conn: conn, pro: pro}
  end

  describe "start_link/1" do
    test "starts consumer", meta do
      assert {:ok, _con} = Consumer.start_link(meta.conn, module: ConOne, queue: "consumer")
    end
  end

  describe "stop/2" do
    test "stops consumer", meta do
      assert {:ok, consumer, _queue} = start_consumer(meta)
      assert :ok = Consumer.stop(consumer)
      refute Process.alive?(consumer)
    end

    test "disconnects the amqp channel", meta do
      assert {:ok, consumer, _queue} = start_consumer(meta)

      state = GenServer.call(consumer, :state)

      assert Process.alive?(state.channel.pid)
      assert :ok = Consumer.stop(consumer)

      :timer.sleep(10)

      refute Process.alive?(state.channel.pid)
    end
  end

  @tag capture_log: true
  test "will reconnect when connection stops", meta do
    assert {:ok, consumer, _queue} = start_consumer(meta)

    conn_state = GenServer.call(meta.conn, :state)
    consumer_state1 = GenServer.call(consumer, :state)
    AMQP.Connection.close(conn_state.connection)
    await_consuming(consumer)
    consumer_state2 = GenServer.call(consumer, :state)

    assert consumer_state1.channel.pid != consumer_state2.channel.pid
  end

  test "will consume messages", meta do
    assert {:ok, consumer, queue} = start_consumer(meta)

    signature = publish_message(meta, queue)

    assert_receive {:handle_message, ^signature}
  end

  test "will consume messages with prefetch_count", meta do
    assert {:ok, consumer, queue} = start_consumer(meta, prefetch_count: 3)

    signature1 = publish_message(meta, queue)
    signature2 = publish_message(meta, queue)
    signature3 = publish_message(meta, queue)

    assert_receive {:handle_message, ^signature1}
    assert_receive {:handle_message, ^signature2}
    assert_receive {:handle_message, ^signature3}
  end

  defp start_consumer(meta, opts \\ []) do
    queue = :crypto.strong_rand_bytes(8) |> Base.encode64()
    opts = [module: ConOne, queue: queue, async_connect: false] ++ opts
    {:ok, consumer} = Consumer.start_link(meta.conn, opts)
    await_consuming(consumer)
    {:ok, consumer, queue}
  end

  defp publish_message(meta, queue, opts \\ []) do
    signature = make_ref()
    message = {self(), signature}
    encoded_message = message |> :erlang.term_to_binary() |> Base.encode64()
    Producer.publish(meta.pro, "", queue, encoded_message, opts)
    signature
  end

  defp await_consuming(consumer) do
    state = GenServer.call(consumer, :state)

    if state.consuming do
      :ok
    else
      :timer.sleep(10)
      await_consuming(consumer)
    end
  end
end
