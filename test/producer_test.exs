defmodule Rabbit.ProducerTest do
  use ExUnit.Case, async: false

  alias Rabbit.{Connection, Producer}

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

  defmodule TroublesomeTestProducer do
    use Rabbit.Producer

    @impl Rabbit.Producer
    def init(_type, opts) do
      {:ok, opts}
    end

    @impl Rabbit.Producer
    def handle_setup(state) do
      attempt = Agent.get_and_update(state.setup_opts[:counter], fn n -> {n, n + 1} end)

      if attempt == 0 do
        {:error, :something_went_wrong}
      else
        :ok
      end
    end
  end

  describe "start_link/3" do
    test "starts producer" do
      assert {:ok, connection} = Connection.start_link(TestConnection)
      assert {:ok, _producer} = Producer.start_link(TestProducer, connection: connection)
    end

    test "starts producer with pool_size" do
      assert {:ok, connection} = Connection.start_link(TestConnection)

      assert {:ok, producer} =
               Producer.start_link(TestProducer, connection: connection, pool_size: 2)

      assert [_, _] = GenServer.call(producer, :get_avail_workers)

      assert {:ok, producer} =
               Producer.start_link(TestProducer, connection: connection, pool_size: 3)

      assert [_, _, _] = GenServer.call(producer, :get_avail_workers)
    end

    test "returns error when given bad producer options" do
      {:error, _} = Producer.start_link(TestProducer, connection: "foo")
    end

    test "returns error when given bad pool options" do
      assert {:error, _} = Producer.start_link(TestProducer, pool_size: "foo")
    end
  end

  describe "start_link/3 with :sync_start" do
    test "starts producer with multiple attempts" do
      {:ok, counter} = Agent.start(fn -> 0 end)
      assert {:ok, connection} = Connection.start_link(TestConnection)

      assert {:ok, _producer} =
               Producer.start_link(TroublesomeTestProducer,
                 connection: connection,
                 sync_start: true,
                 setup_opts: [counter: counter]
               )

      assert Agent.get(counter, & &1) == 2
    end
  end

  describe "stop/1" do
    test "stops producer" do
      assert {:ok, connection} = Connection.start_link(TestConnection)
      assert {:ok, producer} = Producer.start_link(TestProducer, connection: connection)
      assert :ok = Producer.stop(producer)
      refute Process.alive?(producer)
    end

    test "disconnects the amqp channel" do
      assert {:ok, connection} = Connection.start_link(TestConnection)

      assert {:ok, producer} = Producer.start_link(TestProducer, connection: connection)

      await_publishing(producer)

      [worker] = GenServer.call(producer, :get_avail_workers)
      state = GenServer.call(worker, :state)

      assert Process.alive?(state.channel.pid)
      assert :ok = Producer.stop(producer)

      :timer.sleep(50)

      refute Process.alive?(state.channel.pid)
    end
  end

  describe "publish/6" do
    test "publishes payload to queue" do
      {:ok, amqp_conn} = AMQP.Connection.open()
      {:ok, amqp_chan} = AMQP.Channel.open(amqp_conn)
      AMQP.Queue.declare(amqp_chan, "foo", auto_delete: true)
      AMQP.Queue.purge(amqp_chan, "foo")

      assert {:ok, connection} = Connection.start_link(TestConnection)
      assert {:ok, producer} = Producer.start_link(TestProducer, connection: connection)

      await_publishing(producer)

      assert :ok = Producer.publish(producer, "", "foo", "bar")

      :timer.sleep(50)

      assert 1 = AMQP.Queue.message_count(amqp_chan, "foo")

      AMQP.Queue.purge(amqp_chan, "foo")
    end
  end

  test "will reconnect when connection stops" do
    {:ok, amqp_conn} = AMQP.Connection.open()
    {:ok, amqp_chan} = AMQP.Channel.open(amqp_conn)
    AMQP.Queue.declare(amqp_chan, "foo", auto_delete: true)

    assert {:ok, connection} = Connection.start_link(TestConnection)
    assert {:ok, producer} = Producer.start_link(TestProducer, connection: connection)

    state = connection_state(connection)
    AMQP.Connection.close(state.connection)
    :timer.sleep(50)

    assert :ok = Producer.publish(producer, "", "foo", "bar")

    AMQP.Queue.purge(amqp_chan, "foo")
  end

  test "producer modules use producer_pool init callback" do
    Process.register(self(), :producer_test)

    defmodule TestProducerTwo do
      use Rabbit.Producer

      @impl Rabbit.Producer
      def init(:producer_pool, opts) do
        send(:producer_test, :init_callback)
        {:ok, opts}
      end

      def init(:producer, opts) do
        {:ok, opts}
      end
    end

    assert {:ok, connection} = Connection.start_link(TestConnection)
    assert {:ok, _producer} = Producer.start_link(TestProducerTwo, connection: connection)
    assert_receive :init_callback
  end

  test "producer modules use producer init callback" do
    Process.register(self(), :producer_test)

    defmodule TestProducerThree do
      use Rabbit.Producer

      @impl Rabbit.Producer
      def init(:producer_pool, opts) do
        {:ok, opts}
      end

      def init(:producer, opts) do
        send(:producer_test, :init_callback)
        {:ok, opts}
      end
    end

    assert {:ok, connection} = Connection.start_link(TestConnection)
    assert {:ok, _producer} = Producer.start_link(TestProducerThree, connection: connection)
    assert_receive :init_callback
  end

  test "producer modules use handle_setup/1 callback" do
    Process.register(self(), :producer_test)

    defmodule TestProducerFour do
      use Rabbit.Producer

      @impl Rabbit.Producer
      def init(_type, opts) do
        {:ok, opts}
      end

      @impl Rabbit.Producer
      def handle_setup(state) do
        send(:producer_test, {:handle_setup_callback, state})
        :ok
      end
    end

    assert {:ok, connection} = Connection.start_link(TestConnection)
    assert {:ok, _producer} = Producer.start_link(TestProducerFour, connection: connection)
    assert_receive {:handle_setup_callback, %{channel: channel}}
    assert channel
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

  defp connection_state(connection) do
    Connection.transaction(connection, &GenServer.call(&1, :state))
  end
end
