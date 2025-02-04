defmodule Archivist.MixProject do
  use Mix.Project

  def project do
    [
      app: :archivist,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Archivist.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["test/support", "lib"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:mox, "~> 1.2", only: :test},
      {:nimble_csv, "~> 1.2"},
      {:ollama, "~> 0.8.0"},
      {:slugify, "~> 1.3"}
    ]
  end
end
