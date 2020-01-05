defmodule Rabbit.ConnectionPoolTest do
  use ExUnit.Case, async: false

  alias Rabbit.ConnectionPool

  defmodule TestConnectionPool do
    use Rabbit.ConnectionPool

    @impl Rabbit.ConnectionPool
    def init(_type, opts) do
      {:ok, opts}
    end
  end

  describe "start_link/3" do
    test "starts connection pool" do
      assert {:ok, _} = ConnectionPool.start_link(TestConnectionPool)
    end

    test "starts connection pool with pool_size" do
      assert {:ok, connection_pool} = ConnectionPool.start_link(TestConnectionPool)

      assert [_] = GenServer.call(connection_pool, :get_avail_workers)
      assert {:ok, connection_pool} = ConnectionPool.start_link(TestConnectionPool, pool_size: 3)
      assert [_, _, _] = GenServer.call(connection_pool, :get_avail_workers)
    end

    test "returns error when given bad pool options" do
      assert {:error, _} = ConnectionPool.start_link(TestConnectionPool, pool_size: "foo")
    end
  end

  describe "subscribe/2" do
    test "subscribes to connection in the pool" do
      assert {:ok, connection_pool} = ConnectionPool.start_link(TestConnectionPool)

      state = ConnectionPool.transaction(connection_pool, &GenServer.call(&1, :state))

      refute MapSet.member?(state.subscribers, self())

      ConnectionPool.subscribe(connection_pool)
      state = ConnectionPool.transaction(connection_pool, &GenServer.call(&1, :state))

      assert MapSet.member?(state.subscribers, self())
    end

    test "sends raw connection to subscriber" do
      assert {:ok, connection_pool} = ConnectionPool.start_link(TestConnectionPool)

      ConnectionPool.subscribe(connection_pool)

      assert_receive {:connected, %_{}}
    end
  end

  describe "stop/1" do
    test "stops connection pool" do
      assert {:ok, connection_pool} = ConnectionPool.start_link(TestConnectionPool)
      assert :ok = ConnectionPool.stop(connection_pool)
      refute Process.alive?(connection_pool)
    end

    test "disconnects the amqp connection" do
      assert {:ok, connection_pool} = ConnectionPool.start_link(TestConnectionPool)

      state = ConnectionPool.transaction(connection_pool, &GenServer.call(&1, :state))

      assert Process.alive?(state.connection.pid)
      assert :ok = ConnectionPool.stop(connection_pool)
      refute Process.alive?(state.connection.pid)
    end

    test "publishes disconnect to subscribers" do
      assert {:ok, connection_pool} = ConnectionPool.start_link(TestConnectionPool)

      ConnectionPool.subscribe(connection_pool)

      assert :ok = ConnectionPool.stop(connection_pool)
      assert_receive {:disconnected, :stopped}
    end
  end

  describe "fetch/2" do
    test "fetchs raw connection from pool" do
      assert {:ok, connection_pool} = ConnectionPool.start_link(TestConnectionPool)
      assert {:ok, %_{}} = ConnectionPool.fetch(connection_pool)
    end
  end

  test "connection pool modules use init callback" do
    Process.register(self(), :connection_pool_test)

    defmodule TestConnectionPoolTwo do
      use Rabbit.ConnectionPool

      @impl Rabbit.ConnectionPool
      def init(:connection_pool, opts) do
        send(:connection_pool_test, :init_callback)
        {:ok, opts}
      end

      def init(_type, opts) do
        {:ok, opts}
      end
    end

    assert {:ok, _connection_pool} = ConnectionPool.start_link(TestConnectionPoolTwo)
    assert_receive :init_callback
  end
end
