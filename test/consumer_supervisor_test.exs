defmodule Rabbit.ConsumerSupervisorTest do
  use ExUnit.Case, async: false

  alias Rabbit.{Connection, ConsumerSupervisor}

  defmodule TestConnection do
    use Rabbit.Connection

    @impl Rabbit.Connection
    def init(_type, opts) do
      {:ok, opts}
    end
  end

  defmodule TestConsumers do
    use Rabbit.ConsumerSupervisor

    @impl Rabbit.ConsumerSupervisor
    def init(:consumer_supervisor, _consumers) do
      consumers = [
        [connection: TestConnection, queue: queue_name()],
        [connection: TestConnection, queue: queue_name()]
      ]

      {:ok, consumers}
    end

    def init(:consumer, opts) do
      {:ok, opts}
    end

    @impl Rabbit.ConsumerSupervisor
    def handle_setup(state) do
      AMQP.Queue.declare(state.channel, state.queue, auto_delete: true)
      AMQP.Queue.purge(state.channel, state.queue)

      :ok
    end

    @impl Rabbit.ConsumerSupervisor
    def handle_message(msg) do
      decoded_payload = Base.decode64!(msg.payload)
      {pid, ref} = :erlang.binary_to_term(decoded_payload)
      send(pid, {:handle_message, ref})
      :ok
    end

    @impl Rabbit.ConsumerSupervisor
    def handle_error(_) do
      :ok
    end

    defp queue_name do
      :crypto.strong_rand_bytes(8) |> Base.encode64()
    end
  end

  setup_all do
    {:ok, connection} = Connection.start_link(TestConnection, [], name: TestConnection)
    %{connection: connection}
  end

  describe "start_link/2" do
    test "starts consumer supervsior" do
      assert {:ok, _} = ConsumerSupervisor.start_link(TestConsumers)
    end
  end

  describe "stop/0" do
    test "stops consumer supervisor" do
      assert {:ok, consumer_sup} = ConsumerSupervisor.start_link(TestConsumers)
      assert :ok = ConsumerSupervisor.stop(consumer_sup)
      refute Process.alive?(consumer_sup)
    end
  end

  test "will start as many consumers as listed in consumers callback" do
    assert {:ok, consumer_sup} = ConsumerSupervisor.start_link(TestConsumers)
    assert [_, _] = Supervisor.which_children(consumer_sup)
  end
end
