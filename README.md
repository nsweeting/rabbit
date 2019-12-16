# Rabbit

[![Build Status](https://travis-ci.org/nsweeting/rabbit.svg?branch=master)](https://travis-ci.org/nsweeting/rabbit)
[![Rabbit Version](https://img.shields.io/hexpm/v/rabbit.svg)](https://hex.pm/packages/rabbit)

Rabbit is a set of tools for building applications with RabbitMQ.

## Installation

The package can be installed by adding `rabbit` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:rabbit, "~> 0.8"}
  ]
end
```

## Documentation

Please see [HexDocs](https://hexdocs.pm/rabbit) for additional documentation.

## [Connections](https://hexdocs.pm/rabbit/Rabbit.Connection.html)

Connections form the basis of any application that is working with RabbitMQ. A
connection module is needed by all the other modules included with Rabbit.

```elixir
defmodule MyConnection do
  use Rabbit.Connection

  def start_link(opts \\ []) do
    Rabbit.Connection.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Callbacks

  @impl Rabbit.Connection
  def init(:connection, opts) do
    # Perform runtime config
    uri = System.get_env("RABBITMQ_URI") || "amqp://guest:guest@127.0.0.1:5672"
    opts = Keyword.put(opts, :uri, uri)

    {:ok, opts}
  end
end

MyConnection.start_link()
```

## [Consumers](https://hexdocs.pm/rabbit/Rabbit.Consumer.html)

Consumers are the "workers" of your application. They must be provided a connection
module and queue to consume. Every message recieved is then passed along to your
`handle_message/1` callback within its own process.

You can optionally implement the `handle_setup/2` callback to perform any work
needed to declare queues/exchanges/bindings.

```elixir
defmodule MyConsumer do
  use Rabbit.Consumer

  def start_link(opts \\ []) do
    Rabbit.Consumer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Callbacks

  @impl Rabbit.Consumer
  def init(:consumer, opts) do
    # Perform runtime config
    {:ok, opts}
  end

  @impl Rabbit.Consumer
  def handle_setup(channel, queue) do
    # Optional callback to perform any exchange or queue setup
    AMQP.Queue.declare(channel, queue)
    :ok
  end

  @impl Rabbit.Consumer
  def handle_message(message) do
    # Handle message consumption
    IO.inspect(message.payload)
    {:ack, message}
  end

  @impl Rabbit.Consumer
  def handle_error(message) do
    # Handle message errors
    {:nack, message}
  end
end

MyConsumer.start_link(connection: MyConnection, queue: "my_queue", prefetch_count: 10)
```

## [Consumer Supervisors](https://hexdocs.pm/rabbit/Rabbit.ConsumerSupervisor.html)

Consumer supervisors provide an easy way to start and supervise multiple consumer
processes. Rather than creating a module for each consumer and implementing
repetitive logic - the same callbacks are used across all consumers.

```elixir
defmodule MyConsumerSupervisor do
  use Rabbit.ConsumerSupervisor

  def start_link(consumers \\ []) do
    Rabbit.ConsumerSupervisor.start_link(__MODULE__, consumers, name: __MODULE__)
  end

  # Callbacks

  @impl Rabbit.ConsumerSupervisor
  def init(:consumer_supervisor, _consumers) do
    # Perform runtime config for the consumer supervisor
    consumers = [
      [connection: MyConnection, queue: "my_queue1", prefetch_count: 5],
      [connection: MyConnection, queue: "my_queue2", prefetch_count: 10],
    ]

    {:ok, consumers}
  end

  def init(:consumer, opts) do
    # Perform runtime config per consumer
    {:ok, opts}
  end

  @impl Rabbit.ConsumerSupervisor
  def handle_setup(channel, queue) do
    # Optional callback to perform any exchange or queue setup per consumer
    AMQP.Queue.declare(channel, queue)
    :ok
  end

  @impl Rabbit.ConsumerSupervisor
  def handle_message(message) do
    # Handle message consumption per consumer
    IO.inspect(message.payload)
    {:ack, message}
  end

  @impl Rabbit.ConsumerSupervisor
  def handle_error(message) do
    # Handle message errors per consumer
    {:nack, message}
  end
end

MyConsumerSupervisor.start_link()
```

## [Producers](https://hexdocs.pm/rabbit/Rabbit.Producer.html)

In order to publish messages to RabbitMQ, we must create a producer module. They
must be provided a connection module. The producer will then automatically create
a pool of channels to publish from.

You can optionally implement the `handle_setup/1` callback to perform any work
needed to declare queues/exchanges/bindings.

```elixir
defmodule MyProducer do
  use Rabbit.Producer

  def start_link(opts \\ []) do
    Rabbit.Producer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Callbacks

  @impl Rabbit.Producer
  def init(:producer_pool, opts) do
    # Perform runtime config for the producer pool
    {:ok, opts}
  end

  def init(:producer, opts) do
    # Perform runtime config per producer
    {:ok, opts}
  end
end

MyProducer.start_link(connection: MyConnection)
Rabbit.Producer.publish(MyProducer, "", "my_queue", "hello")
```

## [Initializers](https://hexdocs.pm/rabbit/Rabbit.Initializer.html)

Initializers provide a way to centralize any RabbitMQ setup required by your 
application. In that sense, it should be started BEFORE any of your producers
or consumers.

Using an initializer, you can automatically setup queues, exchanges and bindings
with simple keyword lists.

```elixir
defmodule MyInitializer do
  use Rabbit.Initializer

  def start_link(opts \\ []) do
    Rabbit.Initializer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Callbacks

  @impl Rabbit.Initializer
  def init(:initializer, opts) do
    # Perform runtime config
    {:ok, opts}
  end
end

MyInitializer.start_link(
  connection: MyConnection,
  queues: [
    [name: "my_queue_1"],
    [name: "my_queue_2", durable: true],
  ],
  exchanges: [
    [name: "my_exchange_1"],
    [name: "my_exchange_2", type: :fanout, durable: true],
  ],
  bindings: [
    [type: :queue, source: "my_exchange_1", destination: "my_queue_1", routing_key: "my_key"],
    [type: :exchange, source: "my_exchange_2", destination: "my_exchange_1"]
  ]
)
```