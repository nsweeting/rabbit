defmodule Rabbit.BrokerTest do
  use ExUnit.Case, async: false

  alias Rabbit.Broker

  defmodule TestBroker do
    use Rabbit.Broker

    @impl Rabbit.Broker
    def init(_type, opts) do
      {:ok, opts}
    end

    @impl Rabbit.Broker
    def handle_message(msg) do
      decoded_payload = Base.decode64!(msg.payload)
      {pid, ref, return} = :erlang.binary_to_term(decoded_payload)
      send(pid, {:handle_message, ref})
      {return, msg}
    end

    @impl Rabbit.Broker
    def handle_error(_) do
      :ok
    end
  end

  describe "start_link/2" do
    test "starts a broker" do
      assert {:ok, broker} = Broker.start_link(TestBroker)
      assert is_pid(broker)
    end

    test "starts a broker with connection opts" do
      assert {:ok, broker} = Broker.start_link(TestBroker, connection: [pool_size: 1])
      assert [_] = GenServer.call(TestBroker.Connection, :get_avail_workers)

      Broker.stop(broker)

      assert {:ok, broker} = Broker.start_link(TestBroker, connection: [pool_size: 3])
      assert [_, _, _] = GenServer.call(TestBroker.Connection, :get_avail_workers)
    end
  end
end
