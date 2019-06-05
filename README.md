# Rabbit

[![Build Status](https://travis-ci.org/nsweeting/rabbit.svg?branch=master)](https://travis-ci.org/nsweeting/rabbit)
[![StatBuffer Version](https://img.shields.io/hexpm/v/rabbit.svg)](https://hex.pm/packages/rabbit)

Rabbit is a set of tools for building applications with RabbitMQ.

## Installation

The package can be installed by adding `rabbit` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:rabbit, "~> 0.1"}
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

  # Callbacks

  # Perform runtime config
  def init(opts) do
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

  # Callbacks

  # Perform runtime config
  def init(opts) do
    {:ok, opts}
  end

  # Perform any exchange or queue setup
  def after_connect(channel, queue) do
    AMQP.Queue.declare(channel, queue)
    :ok
  end

  # Handle message consumption
  def handle_message(message) do
    IO.inspect(message.payload)
    {:ack, message}
  end

  # Handle message errors
  def handle_error(message) do
    {:nack, message}
  end
end

MyConsumer.start_link(MyConnection, queue: "my_queue", prefetch_count: 10)
```

Or, create a consumer supervisor:

```elixir
defmodule MyConsumers do
  use Rabbit.ConsumerSupervisor

  # Callbacks

  # Specifiy a list of consumers under the supervisor
  def consumers do
    [
      [queue: "my_queue", prefetch_count: 10],
      [queue: "my_other_queue", prefetch_count: 10]
    ]
  end

  # Perform runtime config per consumer
  def init(opts) do
    {:ok, opts}
  end

  # Perform any exchange or queue setup per consumer
  def after_connect(channel, queue) do
    AMQP.Queue.declare(channel, queue)
    :ok
  end

  # Handle message consumption per consumer
  def handle_message(message) do
    IO.inspect(message.payload)
    {:ack, message}
  end

  # Handle message errors per consumer
  def handle_error(message) do
    {:nack, message}
  end
end

MyConsumers.start_link(MyConnection)
```

## Producers

Create a producer module:

```elixir
defmodule MyProducer do
  use Rabbit.Producer

  # Callbacks

  # Perform runtime config
  def init(opts) do
    {:ok, opts}
  end
end

MyProducer.start_link(MyConnection)
MyProducer.publish("", "my_queue", "hello")
```
