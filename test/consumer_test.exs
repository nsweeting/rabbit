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
    def handle_setup(state) do
      if is_pid(Process.whereis(:consumer_test)), do: send(:consumer_test, :handle_setup_callback)
      AMQP.Queue.declare(state.channel, state.queue, auto_delete: true)
      AMQP.Queue.purge(state.channel, state.queue)
      :ok
    end

    @impl Rabbit.Consumer
    def handle_message(msg) do
      decoded_payload = Base.decode64!(msg.payload)
      {pid, ref, return} = :erlang.binary_to_term(decoded_payload)
      send(pid, {:handle_message, ref, msg})
      {return, msg}
    end

    @impl Rabbit.Consumer
    def handle_error(_) do
      :ok
    end
  end

  defmodule MinimalTestConsumer do
    use Rabbit.Consumer

    @impl Rabbit.Consumer
    def init(:consumer, opts) do
      {:ok, opts}
    end

    @impl Rabbit.Consumer
    def handle_message(_msg) do
    end

    @impl Rabbit.Consumer
    def handle_error(_) do
      :ok
    end
  end

  defmodule AdvancedSetupTestConsumer do
    use Rabbit.Consumer

    @impl Rabbit.Consumer
    def init(:consumer, opts) do
      {:ok, opts}
    end

    @impl Rabbit.Consumer
    def handle_setup(state) do
      %{channel: channel, setup_opts: setup_opts} = state
      {:ok, %{queue: queue}} = AMQP.Queue.declare(channel)
      # Declare an exchange as the default exchange cannot bind queues.
      :ok = AMQP.Exchange.declare(channel, "topic_test", :topic)
      :ok = AMQP.Queue.bind(channel, queue, "topic_test", routing_key: setup_opts[:routing_key])

      send(setup_opts[:test_pid], :handle_advanced_setup_callback)

      {:ok, %{state | queue: queue}}
    end

    @impl Rabbit.Consumer
    def handle_message(_msg) do
    end

    @impl Rabbit.Consumer
    def handle_error(_) do
      :ok
    end
  end

  defmodule ErrorTestConsumer do
    use Rabbit.Consumer

    @impl Rabbit.Consumer
    def init(:consumer, opts) do
      {:ok, opts}
    end

    @impl Rabbit.Consumer
    def handle_setup(state) do
      AMQP.Queue.declare(state.channel, state.queue, auto_delete: true)
      AMQP.Queue.purge(state.channel, state.queue)
      :ok
    end

    @impl Rabbit.Consumer
    def handle_message(msg) do
      decoded_payload = Base.decode64!(msg.payload)
      {_, _, fun} = :erlang.binary_to_term(decoded_payload)
      fun.()
    end

    @impl Rabbit.Consumer
    def handle_error(msg) do
      decoded_payload = Base.decode64!(msg.payload)
      {pid, ref, _} = :erlang.binary_to_term(decoded_payload)
      send(pid, {:handle_error, ref, msg})
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

      state = :sys.get_state(consumer)

      assert Process.alive?(state.channel.pid)
      assert :ok = Consumer.stop(consumer)

      :timer.sleep(10)

      refute Process.alive?(state.channel.pid)
    end
  end

  test "will reconnect when connection stops", meta do
    assert {:ok, consumer, _queue} = start_consumer(meta)

    connection_state = connection_state(meta.connection)
    consumer_state1 = :sys.get_state(consumer)
    Process.exit(connection_state.connection.pid, :killed)
    :timer.sleep(20)
    await_consuming(consumer)
    consumer_state2 = :sys.get_state(consumer)

    assert consumer_state1.channel.pid != consumer_state2.channel.pid
  end

  test "will reconnect when channel stops", meta do
    assert {:ok, consumer, _queue} = start_consumer(meta)

    consumer_state1 = :sys.get_state(consumer)
    Process.exit(consumer_state1.channel.pid, :killed)
    :timer.sleep(20)
    await_consuming(consumer)
    consumer_state2 = :sys.get_state(consumer)

    assert consumer_state1.channel.pid != consumer_state2.channel.pid
  end

  test "will reconnect when worker stops", meta do
    assert {:ok, consumer, _queue} = start_consumer(meta)

    consumer_state1 = :sys.get_state(consumer)
    worker = Enum.random(consumer_state1.workers)
    Process.exit(worker, :kill)
    :timer.sleep(20)
    await_consuming(consumer)
    consumer_state2 = :sys.get_state(consumer)

    assert consumer_state1.workers != consumer_state2.workers
  end

  test "will consume messages", meta do
    assert {:ok, _consumer, queue} = start_consumer(meta)

    ref = publish_message(meta, queue)

    assert_receive {:handle_message, ^ref, _}
  end

  test "will consume messages with prefetch_count", meta do
    assert {:ok, _consumer, queue} = start_consumer(meta, prefetch_count: 3)

    ref1 = publish_message(meta, queue)
    ref2 = publish_message(meta, queue)
    ref3 = publish_message(meta, queue)

    assert_receive {:handle_message, ^ref1, _}
    assert_receive {:handle_message, ^ref2, _}
    assert_receive {:handle_message, ^ref3, _}
  end

  test "consumer modules use init callback", meta do
    Process.register(self(), :consumer_test)

    assert {:ok, _, _} = start_consumer(meta)
    assert_receive :init_callback
  end

  test "consumer modules use handle_setup/2 callback", meta do
    Process.register(self(), :consumer_test)

    assert {:ok, _, _} = start_consumer(meta)
    assert_receive :handle_setup_callback
  end

  test "consumer module uses handle_setup/1 callback", meta do
    assert {:ok, _, _} =
             start_consumer(AdvancedSetupTestConsumer, meta,
               setup_opts: [test_pid: self(), routing_key: "routing.route"]
             )

    assert_receive :handle_advanced_setup_callback
  end

  test "handle_setup is optional if the queue already exists", meta do
    state = connection_state(meta.connection)
    {:ok, channel} = AMQP.Channel.open(state.connection)
    queue = queue_name()
    AMQP.Queue.declare(channel, queue, auto_delete: true)

    assert {:ok, _, _} = start_consumer(MinimalTestConsumer, meta, queue: queue)
  end

  test "stops the server if the queue is not specified", meta do
    Process.flag(:trap_exit, true)
    {:ok, consumer} = Consumer.start_link(MinimalTestConsumer, connection: meta.connection)
    Process.monitor(consumer)

    assert_receive {:EXIT, _pid, :no_queue_given}
  end

  test "will ack messages based on return value", meta do
    state = connection_state(meta.connection)
    {:ok, channel} = AMQP.Channel.open(state.connection)
    queue = queue_name()
    AMQP.Queue.declare(channel, queue, auto_delete: true)

    assert AMQP.Queue.message_count(channel, queue) == 0

    publish_message(meta, queue, msg: :ack)
    :timer.sleep(50)

    assert AMQP.Queue.message_count(channel, queue) == 1
    assert {:ok, _consumer, queue} = start_consumer(meta, queue: queue)
    assert AMQP.Queue.message_count(channel, queue) == 0
  end

  test "will include custom_meta in the handle_message message", meta do
    assert {:ok, _consumer, queue} =
             start_consumer(meta, prefetch_count: 3, custom_meta: %{foo: "bar"})

    ref = publish_message(meta, queue)

    assert_receive {:handle_message, ^ref, msg}
    assert msg.custom_meta == %{foo: "bar"}
  end

  test "will run the handle_error/1 callback on exceptions", meta do
    {:ok, _consumer, queue} = start_consumer(ErrorTestConsumer, meta, [])
    error = fn -> raise "boom" end
    ref = publish_message(meta, queue, msg: error)

    assert_receive {:handle_error, ^ref, msg}
    assert msg.error_reason == %RuntimeError{message: "boom"}
  end

  test "will run the handle_error/1 callback on linked processes crashing", meta do
    {:ok, _consumer, queue} = start_consumer(ErrorTestConsumer, meta, [])

    error = fn ->
      spawn_link(fn -> raise "boom" end)
      :timer.sleep(5000)
    end

    ref = publish_message(meta, queue, msg: error)

    assert_receive {:handle_error, ^ref, msg}
    assert msg.error_reason == %RuntimeError{message: "boom"}
  end

  test "will run the handle_error/1 callback on process exits", meta do
    {:ok, _consumer, queue} = start_consumer(ErrorTestConsumer, meta, [])

    error = fn ->
      Process.exit(self(), :boom)
      :timer.sleep(5000)
    end

    ref = publish_message(meta, queue, msg: error)

    assert_receive {:handle_error, ^ref, msg}
    assert msg.error_reason == :boom
  end

  defp start_consumer(meta, opts \\ []), do: start_consumer(TestConsumer, meta, opts)

  defp start_consumer(module, meta, opts) do
    queue = Keyword.get(opts, :queue, queue_name())
    opts = [connection: meta.connection, queue: queue] ++ opts
    {:ok, consumer} = Consumer.start_link(module, opts)
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
    state = :sys.get_state(consumer)

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

  defp connection_state(connection) do
    Connection.transaction(connection, &:sys.get_state(&1))
  end
end
