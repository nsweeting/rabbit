defmodule Rabbit.ConsumerTest do
  use ExUnit.Case, async: false

  alias Rabbit.{Connection, Consumer, Producer}

  defmodule TestConnection do
    use Rabbit.Connection

    @impl Rabbit.Connection
    def init(_type, opts) do
      {:ok, opts}
    end
  end

  defmodule TestProducer do
    use Rabbit.Producer

    @impl Rabbit.Producer
    def init(_type, opts) do
      {:ok, opts}
    end
  end

  defmodule TestConsumer do
    use Rabbit.Consumer

    @impl Rabbit.Consumer
    def init(:consumer, opts) do
      if is_pid(Process.whereis(:consumer_test)), do: send(:consumer_test, :init_callback)
      {:ok, opts}
    end

    @impl Rabbit.Consumer
    def handle_setup(chan, queue) do
      if is_pid(Process.whereis(:consumer_test)), do: send(:consumer_test, :handle_setup_callback)
      AMQP.Queue.declare(chan, queue, auto_delete: true)
      AMQP.Queue.purge(chan, queue)
      :ok
    end

    @impl Rabbit.Consumer
    def handle_message(msg) do
      decoded_payload = Base.decode64!(msg.payload)
      {pid, ref, return} = :erlang.binary_to_term(decoded_payload)
      send(pid, {:handle_message, ref})
      {return, msg}
    end

    @impl Rabbit.Consumer
    def handle_error(_) do
      :ok
    end
  end

  setup do
    {:ok, connection} = Connection.start_link(TestConnection)
    {:ok, producer} = Producer.start_link(TestProducer, connection: connection)
    %{connection: connection, producer: producer}
  end

  describe "start_link/3" do
    test "starts consumer", meta do
      assert {:ok, _con} =
               Consumer.start_link(TestConsumer, connection: meta.connection, queue: "consumer")
    end

    test "returns error when given bad consumer options" do
      assert {:error, _} = Consumer.start_link(TestConsumer, connection: 1)
    end
  end

  describe "stop/1" do
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

  test "will reconnect when connection stops", meta do
    assert {:ok, consumer, _queue} = start_consumer(meta)

    connection_state = Connection.transaction(meta.connection, &GenServer.call(&1, :state))
    consumer_state1 = GenServer.call(consumer, :state)
    AMQP.Connection.close(connection_state.connection)
    await_consuming(consumer)
    consumer_state2 = GenServer.call(consumer, :state)

    assert consumer_state1.channel.pid != consumer_state2.channel.pid
  end

  test "will consume messages", meta do
    assert {:ok, consumer, queue} = start_consumer(meta)

    ref = publish_message(meta, queue)

    assert_receive {:handle_message, ^ref}
  end

  test "will consume messages with prefetch_count", meta do
    assert {:ok, consumer, queue} = start_consumer(meta, prefetch_count: 3)

    ref1 = publish_message(meta, queue)
    ref2 = publish_message(meta, queue)
    ref3 = publish_message(meta, queue)

    assert_receive {:handle_message, ^ref1}
    assert_receive {:handle_message, ^ref2}
    assert_receive {:handle_message, ^ref3}
  end

  test "consumer modules use init callback", meta do
    Process.register(self(), :consumer_test)
    assert {:ok, _, _} = start_consumer(meta)
    assert_receive :init_callback
  end

  test "consumer modules use handle_setup callback", meta do
    Process.register(self(), :consumer_test)
    assert {:ok, _, _} = start_consumer(meta)
    assert_receive :handle_setup_callback
  end

  test "will ack messages based on return value", meta do
    state = Connection.transaction(meta.connection, &GenServer.call(&1, :state))
    {:ok, channel} = AMQP.Channel.open(state.connection)
    queue = queue_name()
    AMQP.Queue.declare(channel, queue, auto_delete: true)

    assert AMQP.Queue.message_count(channel, queue) == 0

    publish_message(meta, queue, msg: :ack)
    :timer.sleep(50)

    assert AMQP.Queue.message_count(channel, queue) == 1
    assert {:ok, consumer, queue} = start_consumer(meta, queue: queue)
    assert AMQP.Queue.message_count(channel, queue) == 0
  end

  defp start_consumer(meta, opts \\ []) do
    queue = Keyword.get(opts, :queue, queue_name())
    opts = [connection: meta.connection, queue: queue] ++ opts
    {:ok, consumer} = Consumer.start_link(TestConsumer, opts)
    await_consuming(consumer)
    {:ok, consumer, queue}
  end

  defp publish_message(meta, queue, opts \\ []) do
    signature = make_ref()
    message = {self(), signature, Keyword.get(opts, :msg)}
    encoded_message = message |> :erlang.term_to_binary() |> Base.encode64()
    Producer.publish(meta.producer, "", queue, encoded_message, opts)
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

  defp queue_name do
    :crypto.strong_rand_bytes(8) |> Base.encode64()
  end
end
