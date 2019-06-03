defmodule Rabbit.ConsumerTest do
  use ExUnit.Case

  alias Rabbit.{Consumer, Connection, Producer}

  defmodule ConOne do
    use Rabbit.Consumer

    def after_connect(chan, queue) do
      AMQP.Queue.declare(chan, queue)
      AMQP.Queue.purge(chan, queue)

      :ok
    end

    def handle_message(msg) do
      send(String.to_atom(msg.payload), {:handle_message, msg.payload})
      {:ack, msg}
    end

    def handle_error(msg) do
      {:nack, msg}
    end
  end

  setup do
    {:ok, conn} = Connection.start_link()
    {:ok, pro} = Producer.start_link(conn, async_connect: false)
    %{conn: conn, pro: pro}
  end

  describe "start_link/1" do
    test "starts consumer", meta do
      assert {:ok, _con} = Consumer.start_link(meta.conn, module: ConOne, queue: "foo")
    end
  end

  describe "stop/2" do
    test "stops consumer", meta do
      assert {:ok, con} = start_consumer(meta)
      assert :ok = Consumer.stop(con)
      refute Process.alive?(con)
    end

    test "disconnects the amqp channel", meta do
      assert {:ok, con} = start_consumer(meta)

      state = GenServer.call(con, :state)

      assert Process.alive?(state.channel.pid)
      assert :ok = Consumer.stop(con)
      refute Process.alive?(state.channel.pid)
    end
  end

  defp start_consumer(meta) do
    Consumer.start_link(meta.conn, module: ConOne, queue: "foo", async_connect: false)
  end
end
