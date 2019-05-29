defmodule Rabbit.ConnectionTest do
  use ExUnit.Case

  alias Rabbit.Connection

  describe "start_link/1" do
    test "start connection" do
      assert {:ok, conn} = Connection.start_link()
      assert {:ok, true} = Connection.alive?(conn)
    end

    test "start connection with uri" do
      assert {:ok, conn} = Connection.start_link(uri: "amqp://guest:guest@localhost")
      assert {:ok, true} = Connection.alive?(conn)
    end

    test "start connection with name" do
      assert {:ok, conn} = Connection.start_link(name: :foo)
      assert {:ok, true} = Connection.alive?(:foo)
    end
  end

  describe "stop/2" do
    test "stops connection" do
      assert {:ok, conn} = Connection.start_link()
      assert :ok = Connection.stop(conn)
      refute Process.alive?(conn)
    end

    test "publishes disconnect to subscribers" do
      assert {:ok, conn} = Connection.start_link()
      assert :ok = Connection.subscribe(conn)
      assert :ok = Connection.stop(conn)
      assert_receive {:disconnected, :stopped}
    end
  end

  describe "subscribe/2" do
    test "subscribes to connection" do
      assert {:ok, conn} = Connection.start_link()
      assert :ok = Connection.subscribe(conn)
      assert_receive {:connected, %AMQP.Connection{}}
    end
  end

  describe "unsubscribe/2" do
    test "unsubscribes to connection" do
      assert {:ok, conn} = Connection.start_link()
      assert :ok = Connection.subscribe(conn)
      assert_receive {:connected, %AMQP.Connection{}}
      assert :ok = Connection.unsubscribe(conn)
      assert :ok = Connection.stop(conn)
      refute_receive {:disconnected, :stopped}
    end
  end

  @tag capture_log: true
  test "will reconnect when connection stops" do
    assert {:ok, conn} = Connection.start_link()
    assert :ok = Connection.subscribe(conn)
    assert_receive {:connected, %AMQP.Connection{} = raw_conn}
    AMQP.Connection.close(raw_conn)
    assert_receive {:disconnected, {:shutdown, :normal}}
    assert_receive {:connected, %AMQP.Connection{}}
  end
end
