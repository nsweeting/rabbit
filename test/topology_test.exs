defmodule Rabbit.TopologyTest do
  use ExUnit.Case, async: false

  alias Rabbit.{Connection, Consumer, Producer, Topology}

  @moduletag :capture_log

  defmodule TestConnection do
    use Rabbit.Connection

    @impl Rabbit.Connection
    def init(_type, opts) do
      {:ok, opts}
    end
  end

  defmodule TestBadConnection do
    use GenServer

    def start_link do
      GenServer.start_link(__MODULE__, :ok)
    end

    def init(_type, opts) do
      {:ok, opts}
    end

    @impl GenServer
    def init(_arg) do
      {:ok, :ok}
    end

    @impl GenServer
    def handle_call({:checkout, _, _}, _from, state) do
      {:reply, self(), state}
    end

    def handle_call(:fetch, _from, state) do
      {:reply, {:error, :no_connection}, state}
    end

    @impl GenServer
    def handle_cast(_, state) do
      {:noreply, state}
    end
  end

  defmodule TestTopology do
    use Rabbit.Topology

    def start_link(opts) do
      Rabbit.Topology.start_link(__MODULE__, opts)
    end

    @impl Rabbit.Topology
    def init(:topology, opts) do
      {:ok, opts}
    end
  end

  defmodule TestProducer do
    use Rabbit.Producer

    @impl Rabbit.Producer
    def init(_type, opts) do
      {:ok, opts}
    end
  end

  defmodule TestConsumer do
    use Rabbit.Consumer

    @impl Rabbit.Consumer
    def init(:consumer, opts) do
      {:ok, opts}
    end

    @impl Rabbit.Consumer
    def handle_message(msg) do
      decoded_payload = Base.decode64!(msg.payload)
      {pid, ref} = :erlang.binary_to_term(decoded_payload)
      send(pid, {:handle_message, ref})
      {:ack, msg}
    end

    @impl Rabbit.Consumer
    def handle_error(_) do
      :ok
    end
  end

  setup do
    {:ok, connection} = Connection.start_link(TestConnection)
    {:ok, producer} = Producer.start_link(TestProducer, connection: connection)
    %{connection: connection, producer: producer}
  end

  describe "start_link/3" do
    test "starts a topology", meta do
      queue = random_name()
      exchange = random_name()
      routing_key = random_name()

      opts = [
        connection: meta.connection,
        queues: [
          [name: queue, auto_delete: true]
        ],
        exchanges: [
          [name: exchange, auto_delete: true]
        ],
        bindings: [
          [type: :queue, source: exchange, destination: queue, routing_key: routing_key]
        ]
      ]

      assert {:ok, _} = Topology.start_link(TestTopology, opts)
      assert {:ok, _consumer} = start_consumer(meta, queue)

      ref = publish_message(meta, exchange, routing_key)

      assert_receive {:handle_message, ^ref}
    end

    test "will return an error if there is no connection" do
      {:ok, connection} = TestBadConnection.start_link()

      assert {:error, {:no_connection, _}} =
               start_supervised({TestTopology, connection: connection, retry_max: 1})
    end

    test "returns error when given bad topology options" do
      assert {:error, _} = start_supervised({TestTopology, connection: 1})
    end
  end

  defp publish_message(meta, exchange, routing_key, opts \\ []) do
    signature = make_ref()
    message = {self(), signature}
    encoded_message = message |> :erlang.term_to_binary() |> Base.encode64()
    Producer.publish(meta.producer, exchange, routing_key, encoded_message, opts)
    signature
  end

  defp start_consumer(meta, queue, opts \\ []) do
    opts = [connection: meta.connection, queue: queue] ++ opts
    {:ok, consumer} = Consumer.start_link(TestConsumer, opts)
    await_consuming(consumer)
    {:ok, consumer}
  end

  defp await_consuming(consumer) do
    state = GenServer.call(consumer, :state)

    if state.consuming do
      :ok
    else
      :timer.sleep(10)
      await_consuming(consumer)
    end
  end

  defp random_name do
    :crypto.strong_rand_bytes(8) |> Base.encode64()
  end
end
