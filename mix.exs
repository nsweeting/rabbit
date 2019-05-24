defmodule Rabbit.MixProject do
  use Mix.Project

  def project do
    [
      app: :rabbit,
      version: "0.1.0",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:lager, :logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:amqp, "~> 1.1"},
      {:poolboy, "~> 1.5"},
      {:keyword_validator, "~> 0.2"},
      {:jason, "~> 1.1", optional: true},
      {:benchee, "~> 1.0", only: :dev}
    ]
  end
end
