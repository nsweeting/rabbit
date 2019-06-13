# Rabbit

[![Build Status](https://travis-ci.org/nsweeting/rabbit.svg?branch=master)](https://travis-ci.org/nsweeting/rabbit)
[![StatBuffer Version](https://img.shields.io/hexpm/v/rabbit.svg)](https://hex.pm/packages/rabbit)

Rabbit is a set of tools for building applications with RabbitMQ.

## Installation

The package can be installed by adding `rabbit` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:rabbit, "~> 0.3"}
  ]
end
```

## Documentation

Please see [HexDocs](https://hexdocs.pm/rabbit) for additional documentation.

## Connections

Create a connection module:

```elixir
defmodule MyConnection do
  use Rabbit.Connection

  def start_link(opts \\ []) do
    Rabbit.Connection.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Callbacks

  @impl Rabbit.Connection
  def init(_type, opts) do
    # Perform runtime config
    uri = System.get_env("RABBITMQ_URI") || "amqp://guest:guest@127.0.0.1:5672"
    opts = Keyword.put(opts, :uri, uri)

    {:ok, opts}
  end
end

MyConnection.start_link()
```

## Consumers

Create a consumer module:

```elixir
defmodule MyConsumer do
  use Rabbit.Consumer

  def start_link(opts \\ []) do
    Rabbit.Consumer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Callbacks

  @impl Rabbit.Consumer
  def init(_type, opts) do
    # Perform runtime config
    {:ok, opts}
  end

  @impl Rabbit.Consumer
  def handle_setup(channel, queue) do
    # Perform any exchange or queue setup
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

Or, create a consumer supervisor:

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
    # Perform any exchange or queue setup per consumer
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

## Producers

Create a producer module:

```elixir
defmodule MyProducer do
  use Rabbit.Producer

  def start_link(opts \\ []) do
    Rabbit.Producer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Callbacks

  # Perform runtime config
  def init(:producer, opts) do
    {:ok, opts}
  end
end

MyProducer.start_link(connection: MyConnection)
Rabbit.Producer.publish(MyProducer, "", "my_queue", "hello")
```
