defmodule Rabbit.ConsumerSupervisorTest do
  use ExUnit.Case

  alias Rabbit.{Connection, ConsumerSupervisor, Producer}

  defmodule ConsumersOne do
    use Rabbit.ConsumerSupervisor

    def consumers do
      [
        [queue: queue_name()],
        [queue: queue_name()]
      ]
    end

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

    defp queue_name do
      :crypto.strong_rand_bytes(8) |> Base.encode64()
    end
  end

  setup do
    {:ok, connection} = Connection.start_link()
    {:ok, producer} = Producer.start_link(connection)
    %{connection: connection, producer: producer}
  end

  describe "start_link/2" do
    test "starts consumer supervsior", meta do
      assert {:ok, _} = ConsumersOne.start_link(meta.connection)
    end
  end

  describe "stop/0" do
    test "stops consumer supervisor", meta do
      assert {:ok, consumer_sup} = ConsumersOne.start_link(meta)
      assert :ok = ConsumersOne.stop()
      refute Process.alive?(consumer_sup)
    end
  end

  test "will start as many consumers as listed in consumers callback", meta do
    assert {:ok, _} = ConsumersOne.start_link(meta.connection)
    assert [_, _] = Supervisor.which_children(ConsumersOne)
  end
end
