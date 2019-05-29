# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :logger, level: :error

config :lager,
  error_logger_redirect: false,
  handlers: [level: :critical]
