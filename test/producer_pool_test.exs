defmodule Rabbit.ProducerPoolTest do
  use ExUnit.Case, async: false

  alias Rabbit.{Connection, ProducerPool}

  defmodule TestConnection do
    use Rabbit.Connection

    @impl Rabbit.Connection
    def init(_type, opts) do
      {:ok, opts}
    end
  end

  defmodule TestProducerPool do
    use Rabbit.ProducerPool

    @impl Rabbit.ProducerPool
    def init(_type, opts) do
      {:ok, opts}
    end
  end

  describe "start_link/3" do
    test "starts producer pool" do
      assert {:ok, connection} = Connection.start_link(TestConnection)

      assert {:ok, _producer_pool} =
               ProducerPool.start_link(TestProducerPool, connection: connection)
    end

    test "starts producer pool with pool_size" do
      assert {:ok, connection} = Connection.start_link(TestConnection)

      assert {:ok, producer_pool} =
               ProducerPool.start_link(TestProducerPool, connection: connection, pool_size: 2)

      assert [_, _] = GenServer.call(producer_pool, :get_avail_workers)

      assert {:ok, producer_pool} =
               ProducerPool.start_link(TestProducerPool, connection: connection, pool_size: 3)

      assert [_, _, _] = GenServer.call(producer_pool, :get_avail_workers)
    end

    test "returns error when given bad pool options" do
      assert {:error, _} = ProducerPool.start_link(TestProducerPool, pool_size: "foo")
    end
  end

  describe "stop/1" do
    test "stops producer pool" do
      assert {:ok, connection} = Connection.start_link(TestConnection)

      assert {:ok, producer_pool} =
               ProducerPool.start_link(TestProducerPool, connection: connection)

      assert :ok = ProducerPool.stop(producer_pool)
      refute Process.alive?(producer_pool)
    end

    test "disconnects the amqp channel" do
      assert {:ok, connection} = Connection.start_link(TestConnection)

      assert {:ok, producer_pool} =
               ProducerPool.start_link(TestProducerPool, connection: connection)

      await_publishing(producer_pool)

      [worker] = GenServer.call(producer_pool, :get_avail_workers)
      state = GenServer.call(worker, :state)

      assert Process.alive?(state.channel.pid)
      assert :ok = ProducerPool.stop(producer_pool)

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

      assert {:ok, producer_pool} =
               ProducerPool.start_link(TestProducerPool, connection: connection)

      await_publishing(producer_pool)

      assert :ok = ProducerPool.publish(producer_pool, "", "foo", "bar")

      :timer.sleep(50)

      assert 1 = AMQP.Queue.message_count(amqp_chan, "foo")

      AMQP.Queue.purge(amqp_chan, "foo")
    end
  end

  test "producer pool modules use init callback" do
    Process.register(self(), :producer_test)

    defmodule TestProducerPoolTwo do
      use Rabbit.ProducerPool

      @impl Rabbit.ProducerPool
      def init(:producer_pool, opts) do
        send(:producer_test, :init_callback)
        {:ok, opts}
      end

      def init(_type, opts) do
        {:ok, opts}
      end
    end

    assert {:ok, connection} = Connection.start_link(TestConnection)
    assert {:ok, producer} = ProducerPool.start_link(TestProducerPoolTwo, connection: connection)
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
