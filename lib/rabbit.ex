defmodule Rabbit do
  def start(_, _) do
    Supervisor.start_link([Connection, {Consumer, [Connection]}, {Producer, [Connection]}],
      strategy: :one_for_one
    )
  end
end

defmodule Connection do
  use Rabbit.Connection
end

defmodule Consumer do
  use Rabbit.Consumer

  def init(_) do
    {:ok, queue: "tester"}
  end

  def after_connect(channel, queue) do
    AMQP.Queue.declare(channel, queue, durable: true)

    :ok
  end

  def handle_message(msg) do
    {:reject, msg}
  end

  def handle_error(_) do
    Process.exit(self(), :boom)
  end
end

defmodule Producer do
  use Rabbit.Producer
end
