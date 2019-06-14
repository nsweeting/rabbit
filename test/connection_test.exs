defmodule Rabbit.ConnectionTest do
  use ExUnit.Case

  alias Rabbit.Connection

  defmodule TestConnection do
    use Rabbit.Connection

    @impl Rabbit.Connection
    def init(:connection, opts) do
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

    test "starts a connection with name" do
      assert {:ok, connection} = Connection.start_link(TestConnection, [], name: :foo)
      assert true = Connection.alive?(:foo)
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

      state = GenServer.call(connection, :state)

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

      state = GenServer.call(connection, :state)

      refute MapSet.member?(state.subscribers, self())

      Connection.subscribe(connection)

      state = GenServer.call(connection, :state)

      assert MapSet.member?(state.subscribers, self())
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

  test "removes dead monitors" do
    assert {:ok, connection} = Connection.start_link(TestConnection)

    task =
      Task.async(fn ->
        subscriber = self()
        Connection.subscribe(connection, subscriber)
        state = GenServer.call(connection, :state)

        assert :subscriber = Map.get(state.monitors, subscriber)
      end)

    Task.await(task)
    :timer.sleep(50)
    state = GenServer.call(connection, :state)

    refute Map.has_key?(state.monitors, task.pid)
  end

  test "removes dead subscribers" do
    assert {:ok, connection} = Connection.start_link(TestConnection)

    task =
      Task.async(fn ->
        subscriber = self()
        Connection.subscribe(connection, subscriber)
        state = GenServer.call(connection, :state)

        assert MapSet.member?(state.subscribers, subscriber)
      end)

    Task.await(task)
    :timer.sleep(50)
    state = GenServer.call(connection, :state)

    refute MapSet.member?(state.subscribers, task.pid)
  end

  test "connection modules use init callback" do
    Process.register(self(), :connection_test)

    defmodule TestConnectionTwo do
      use Rabbit.Connection

      @impl Rabbit.Connection
      def init(:connection, opts) do
        send(:connection_test, :init_callback)
        {:ok, opts}
      end
    end

    assert {:ok, _connection} = Connection.start_link(TestConnectionTwo)
    assert_receive :init_callback
  end
end
