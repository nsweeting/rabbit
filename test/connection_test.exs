defmodule Rabbit.ConnectionTest do
  use ExUnit.Case, async: false

  alias Rabbit.Connection

  defmodule TestConnection do
    use Rabbit.Connection

    @impl Rabbit.Connection
    def init(_type, opts) do
      {:ok, opts}
    end
  end

  describe "start_link/2" do
    test "starts a connection" do
      assert {:ok, connection} = Connection.start_link(TestConnection)
      assert true = Connection.alive?(connection)
    end

    test "starts a connection with uri" do
      assert {:ok, connection} =
               Connection.start_link(TestConnection, uri: "amqp://guest:guest@localhost")

      assert true = Connection.alive?(connection)
    end

    test "starts connection with pool_size" do
      assert {:ok, connection} = Connection.start_link(TestConnection)

      assert [_] = GenServer.call(connection, :get_avail_workers)
      assert {:ok, connection} = Connection.start_link(TestConnection, pool_size: 3)
      assert [_, _, _] = GenServer.call(connection, :get_avail_workers)
    end

    test "starts a connection with name" do
      assert {:ok, _connection} = Connection.start_link(TestConnection, [], name: :foo)
      assert true = Connection.alive?(:foo)
    end

    test "returns error when given bad connection options" do
      assert {:error, _} = Connection.start_link(TestConnection, uri: 1)
    end

    test "returns error when given bad pool options" do
      assert {:error, _} = Connection.start_link(TestConnection, pool_size: "foo")
    end
  end

  describe "stop/1" do
    test "stops connection" do
      assert {:ok, connection} = Connection.start_link(TestConnection)
      assert :ok = Connection.stop(connection)
      refute Process.alive?(connection)
    end

    test "disconnects the amqp connection" do
      assert {:ok, connection} = Connection.start_link(TestConnection)

      state = connection_state(connection)

      assert Process.alive?(state.connection.pid)
      assert :ok = Connection.stop(connection)
      refute Process.alive?(state.connection.pid)
    end

    test "publishes disconnect to subscribers" do
      assert {:ok, connection} = Connection.start_link(TestConnection)

      Connection.subscribe(connection)

      assert :ok = Connection.stop(connection)
      assert_receive {:disconnected, :stopped}
    end
  end

  describe "subscribe/2" do
    test "subscribes to connection" do
      assert {:ok, connection} = Connection.start_link(TestConnection)

      state = connection_state(connection)

      refute MapSet.member?(state.subscribers, self())

      Connection.subscribe(connection)
      state = connection_state(connection)

      assert MapSet.member?(state.subscribers, self())
    end

    test "sends raw connection to subscriber" do
      assert {:ok, connection} = Connection.start_link(TestConnection)

      Connection.subscribe(connection)

      assert_receive {:connected, %_{}}
    end
  end

  test "will reconnect when connection stops" do
    assert {:ok, connection} = Connection.start_link(TestConnection)
    assert :ok = Connection.subscribe(connection)
    assert {:ok, raw_conn} = Connection.fetch(connection)

    AMQP.Connection.close(raw_conn)

    assert_receive {:disconnected, {:shutdown, :normal}}
    assert_receive {:connected, %AMQP.Connection{}}
  end

  test "removes dead subscribers" do
    assert {:ok, connection} = Connection.start_link(TestConnection)

    task =
      Task.async(fn ->
        subscriber = self()
        Connection.subscribe(connection, subscriber)
        state = connection_state(connection)

        assert MapSet.member?(state.subscribers, subscriber)
      end)

    Task.await(task)
    :timer.sleep(50)
    state = connection_state(connection)

    refute MapSet.member?(state.subscribers, task.pid)
  end

  test "connection modules use init connection_pool callback" do
    Process.register(self(), :connection_test)

    defmodule TestConnectionTwo do
      use Rabbit.Connection

      @impl Rabbit.Connection
      def init(:connection_pool, opts) do
        send(:connection_test, :init_callback)
        {:ok, opts}
      end

      def init(:connection, opts) do
        {:ok, opts}
      end
    end

    assert {:ok, _connection} = Connection.start_link(TestConnectionTwo)
    assert_receive :init_callback
  end

  test "connection modules use init connection callback" do
    Process.register(self(), :connection_test)

    defmodule TestConnectionThree do
      use Rabbit.Connection

      @impl Rabbit.Connection
      def init(:connection_pool, opts) do
        {:ok, opts}
      end

      def init(:connection, opts) do
        send(:connection_test, :init_callback)
        {:ok, opts}
      end
    end

    assert {:ok, _connection} = Connection.start_link(TestConnectionThree)
    assert_receive :init_callback
  end

  defp connection_state(connection) do
    Connection.transaction(connection, &GenServer.call(&1, :state))
  end
end
