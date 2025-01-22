defmodule Archivist.MixProject do
  use Mix.Project

  def project do
    [
      app: :archivist,
      version: "0.1.0",
      elixir: "~> 1.18",
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

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:bypass, "~> 2.1", only: :test},
      {:ecto_sql, "~> 3.12"},
      {:ecto_sqlite3, "~> 0.18.1"},
      {:file_system, "~> 1.1"},
      {:ollama, "~> 0.8.0"},
      {:req, "~> 0.5.8"}
    ]
  end
end
