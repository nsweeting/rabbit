defmodule Connection do
  use Rabbit.Connection

  def start_link(opts \\ []) do
    Rabbit.Connection.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_type, opts) do
    {:ok, opts}
  end
end

defmodule Producer do
  use Rabbit.Producer

  def start_link(opts \\ []) do
    Rabbit.Producer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_type, opts) do
    {:ok, opts}
  end
end

# Setup the RabbitMQ bench queues
{:ok, conn} = AMQP.Connection.open()
{:ok, chan} = AMQP.Channel.open(conn)
AMQP.Queue.declare(chan, "bench_json")
AMQP.Queue.declare(chan, "bench_etf")

# Start the connection and producer
{:ok, _} = Connection.start_link()
{:ok, _} = Producer.start_link(connection: Connection, pool_size: 10)

Benchee.run(%{
  "publish json" => fn ->
    Rabbit.Producer.publish(
      Producer,
      "",
      "bench_json",
      %{foo: "bar", bar: "baz"},
      content_type: "application/json"
    )
  end,
  "publish etf" => fn ->
    Rabbit.Producer.publish(
      Producer,
      "",
      "bench_etf",
      %{foo: "bar", bar: "baz"},
      content_type: "application/etf"
    )
  end
})

# Purge the RabbitMQ bench queues
:timer.sleep(1_000)
AMQP.Queue.purge(chan, "bench_json")
AMQP.Queue.purge(chan, "bench_etf")
