defmodule Rabbit.ConsumerTest do
  use ExUnit.Case

  alias Rabbit.{Connection, Consumer, Producer}

  defmodule ConsumerOne do
    use Rabbit.Consumer

    def after_connect(chan, queue) do
      AMQP.Queue.declare(chan, queue, auto_delete: true)
      AMQP.Queue.purge(chan, queue)

      :ok
    end

    def handle_message(msg) do
      decoded_payload = Base.decode64!(msg.payload)
      {pid, ref} = :erlang.binary_to_term(decoded_payload)
      send(pid, {:handle_message, ref})
      :ok
    end

    def handle_error(_) do
      :ok
    end
  end

  setup do
    {:ok, connection} = Connection.start_link()
    {:ok, producer} = Producer.start_link(connection)
    %{connection: connection, producer: producer}
  end

  describe "start_link/3" do
    test "starts consumer", meta do
      assert {:ok, _con} =
               Consumer.start_link(meta.connection, module: ConsumerOne, queue: "consumer")
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

  @tag capture_log: true
  test "will reconnect when connection stops", meta do
    assert {:ok, consumer, _queue} = start_consumer(meta)

    connection_state = GenServer.call(meta.connection, :state)
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

  test "creating consumer modules", meta do
    defmodule ConsumerTwo do
      use Rabbit.Consumer

      def after_connect(chan, queue) do
        AMQP.Queue.declare(chan, queue, auto_delete: true)
        AMQP.Queue.purge(chan, queue)

        :ok
      end

      def handle_message(_msg), do: :ok

      def handle_error(_msg), do: :ok
    end

    assert {:ok, consumer} = ConsumerTwo.start_link(meta.connection, queue: queue_name())
    assert true = Process.alive?(consumer)
    assert :ok = await_consuming(consumer)
  end

  test "consumer modules use init callback", meta do
    defmodule ConsumerThree do
      use Rabbit.Consumer

      def init(opts) do
        opts = Keyword.put(opts, :queue, "consumer_three")
        {:ok, opts}
      end

      def after_connect(chan, queue) do
        AMQP.Queue.declare(chan, queue, auto_delete: true)
        AMQP.Queue.purge(chan, queue)

        :ok
      end

      def handle_message(_msg), do: :ok

      def handle_error(_msg), do: :ok
    end

    assert {:ok, consumer} = ConsumerThree.start_link(meta.connection)
    assert true = Process.alive?(consumer)
    assert :ok = await_consuming(consumer)

    state = GenServer.call(consumer, :state)

    assert state.queue == "consumer_three"
  end

  defp start_consumer(meta, opts \\ []) do
    queue = queue_name()
    opts = [module: ConsumerOne, queue: queue] ++ opts
    {:ok, consumer} = Consumer.start_link(meta.connection, opts)
    await_consuming(consumer)
    {:ok, consumer, queue}
  end

  defp publish_message(meta, queue, opts \\ []) do
    signature = make_ref()
    message = {self(), signature}
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
