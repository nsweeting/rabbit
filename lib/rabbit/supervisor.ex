defmodule Rabbit.Supervisor do
  use Supervisor

  alias Rabbit.Naming

  @opts_schema %{
    connection: [default: []],
    channels: [default: []],
    exchanges: [default: []],
    queues: [default: []],
    consumers: [default: []]
  }

  ################################
  # Public API
  ################################

  @spec start_link(atom(), keyword()) :: Supervisor.on_start()
  def start_link(broker, opts) when is_atom(broker) and is_list(opts) do
    naming = Naming.all(broker)
    opts = KeywordValidator.validate!(opts, @opts_schema)

    Supervisor.start_link(__MODULE__, {naming, opts}, name: naming.supervisor)
  end

  ################################
  # Supervisor Callbacks
  ################################

  @doc false
  @impl Supervisor
  def init({naming, opts}) do
    children =
      []
      |> with_connection(naming, opts)
      |> with_initializer(naming, opts)
      |> with_channel_pool(naming, opts)
      |> with_worker_sup(naming, opts)
      |> with_consumer_sup(naming, opts)

    Supervisor.init(children, strategy: :one_for_one)
  end

  ################################
  # Private Helpers
  ################################

  defp with_connection(children, naming, opts) do
    opts = Keyword.get(opts, :connection)

    connection = [
      {Rabbit.Connection, [opts, [name: naming.connection]]}
    ]

    children ++ connection
  end

  defp with_initializer(children, naming, opts) do
    opts = Keyword.take(opts, [:queues, :exchanges])
    opts = Keyword.put(opts, :connection, naming.connection)

    initializer = [
      {Rabbit.Initializer, {opts, [name: naming.initializer]}}
    ]

    children ++ initializer
  end

  defp with_channel_pool(children, naming, opts) do
    opts = Keyword.get(opts, :channels)

    connection = [
      {Rabbit.Channel.Pool, {opts, [connection: naming.connection], [name: naming.channel_pool]}}
    ]

    children ++ connection
  end

  defp with_worker_sup(children, naming, _opts) do
    worker_sup = [
      {Rabbit.Worker.Supervisor, [name: naming.worker_sup]}
    ]

    children ++ worker_sup
  end

  defp with_consumer_sup(children, naming, opts) do
    opts =
      opts
      |> Keyword.take([:consumers])
      |> Keyword.merge(
        connection: naming.connection,
        initializer: naming.initializer,
        worker_sup: naming.worker_sup
      )

    consumer_sup = [
      {Rabbit.Consumer.Supervisor, {opts, [name: naming.consumer_sup]}}
    ]

    children ++ consumer_sup
  end
end
