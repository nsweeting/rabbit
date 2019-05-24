defmodule Rabbit.Exchange do
  @type option ::
          {:durable, boolean()}
          | {:auto_delete, boolean()}
          | {:passive, boolean()}
          | {:internal, boolean()}
  @type options :: [option()]
  @type exchange :: {name :: binary(), type :: atom(), options()}
  @type exchanges :: [exchange()]

  @spec declare(Rabbit.Channel.name(), binary(), atom(), keyword()) :: :ok | {:error, any()}
  def declare(channel, name, type, opts \\ []) do
    AMQP.Exchange.declare(channel, name, type, opts)
  end

  @spec declare_all(AMQP.Channel.t(), exchanges()) :: {:ok, [binary()]} | {:error, any()}
  def declare_all(chan, exchanges) do
    do_declare_all(chan, exchanges, {:ok, []})
  end

  ################################
  # Private Helpers
  ################################

  defp do_declare_all(_chan, [], result) do
    result
  end

  defp do_declare_all(chan, [exchange | exchanges], {:ok, result}) do
    {name, type, opts, bindings} = do_exchange_args(exchange)

    case declare(chan, name, type, opts) do
      :ok ->
        case do_bindings(chan, name, bindings) do
          {:ok, _} -> do_declare_all(chan, exchanges, {:ok, result ++ [name]})
          error -> error
        end

      error ->
        error
    end
  end

  defp do_exchange_args({name, type, opts})
       when is_binary(name) and is_atom(type) and is_list(opts) do
    {bindings, opts} = Keyword.pop(opts, :bindings, [])
    {name, type, opts, bindings}
  end

  defp do_exchange_args(exchange) do
    raise ArgumentError, "invalid exchange: #{inspect(exchange)}"
  end

  defp do_bindings(chan, exchange, bindings) do
    do_bindings(chan, exchange, bindings, {:ok, []})
  end

  defp do_bindings(_chan, _exchange, [], result) do
    result
  end

  defp do_bindings(chan, exchange, [binding | bindings], {:ok, result}) do
    {name, opts} = do_binding_args(binding)

    case AMQP.Exchange.bind(chan, name, exchange, opts) do
      :ok -> do_bindings(chan, exchange, bindings, {:ok, result ++ [exchange]})
      error -> error
    end
  end

  defp do_binding_args(name) when is_binary(name) do
    {name, []}
  end

  defp do_binding_args({name, opts}) when is_binary(name) and is_list(opts) do
    {name, opts}
  end

  defp do_binding_args(binding) do
    raise ArgumentError, "invalid exchange binding: #{inspect(binding)}"
  end
end
