defmodule Rabbit.ConnectionTest do
  use ExUnit.Case

  alias Rabbit.Connection

  describe "start_link/2" do
    test "starts a connection" do
      assert {:ok, connection} = Connection.start_link()
      assert true = Connection.alive?(connection)
    end

    test "starts a connection with uri" do
      assert {:ok, connection} = Connection.start_link(uri: "amqp://guest:guest@localhost")
      assert true = Connection.alive?(connection)
    end

    test "starts a connection with name" do
      assert {:ok, connection} = Connection.start_link([], name: :foo)
      assert true = Connection.alive?(:foo)
    end
  end

  describe "stop/1" do
    test "stops connection" do
      assert {:ok, connection} = Connection.start_link()
      assert :ok = Connection.stop(connection)
      refute Process.alive?(connection)
    end

    test "disconnects the amqp connection" do
      assert {:ok, connection} = Connection.start_link()

      state = GenServer.call(connection, :state)

      assert Process.alive?(state.connection.pid)
      assert :ok = Connection.stop(connection)
      refute Process.alive?(state.connection.pid)
    end

    test "publishes disconnect to subscribers" do
      assert {:ok, connection} = Connection.start_link()

      Connection.subscribe(connection)

      assert :ok = Connection.stop(connection)
      assert_receive {:disconnected, :stopped}
    end
  end

  describe "subscribe/2" do
    test "subscribes to connection" do
      assert {:ok, connection} = Connection.start_link()

      state = GenServer.call(connection, :state)

      refute MapSet.member?(state.subscribers, self())

      Connection.subscribe(connection)

      state = GenServer.call(connection, :state)

      assert MapSet.member?(state.subscribers, self())
    end
  end

  @tag capture_log: true
  test "will reconnect when connection stops" do
    assert {:ok, connection} = Connection.start_link()
    assert :ok = Connection.subscribe(connection)
    assert {:ok, raw_conn} = Connection.fetch(connection)

    AMQP.Connection.close(raw_conn)

    assert_receive {:disconnected, {:shutdown, :normal}}
    assert_receive {:connected, %AMQP.Connection{}}
  end

  test "removes dead monitors" do
    assert {:ok, connection} = Connection.start_link()

    task =
      Task.async(fn ->
        subscriber = self()
        Connection.subscribe(connection, subscriber)
        state = GenServer.call(connection, :state)

        assert :subscriber = Map.get(state.monitors, subscriber)
      end)

    Task.await(task)
    state = GenServer.call(connection, :state)

    refute Map.has_key?(state.monitors, task.pid)
  end

  test "removes dead subscribers" do
    assert {:ok, connection} = Connection.start_link()

    task =
      Task.async(fn ->
        subscriber = self()
        Connection.subscribe(connection, subscriber)
        state = GenServer.call(connection, :state)

        assert MapSet.member?(state.subscribers, subscriber)
      end)

    Task.await(task)
    state = GenServer.call(connection, :state)

    refute MapSet.member?(state.subscribers, task.pid)
  end

  test "creating connection modules" do
    defmodule ConnOne do
      use Rabbit.Connection
    end

    assert {:ok, _} = ConnOne.start_link()
    assert true = ConnOne.alive?()
  end

  test "connection modules use init callback" do
    Process.register(self(), :conn_two)

    defmodule ConnTwo do
      use Rabbit.Connection

      def init(opts) do
        send(:conn_two, :init_callback)
        {:ok, opts}
      end
    end

    assert {:ok, _} = ConnTwo.start_link()
    assert_receive :init_callback
  end
end
