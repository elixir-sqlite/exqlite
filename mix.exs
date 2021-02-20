defmodule Exqlite.MixProject do
  use Mix.Project

  def project do
    [
      app: :exqlite,
      compilers: [:elixir_make] ++ Mix.compilers(),
      deps: deps(),
      description: description(),
      elixir: "~> 1.11",
      elixirc_paths: elixirc_paths(Mix.env()),
      homepage_url: "https://github.com/warmwaffles/exqlite",
      make_clean: ["clean"],
      make_targets: ["all"],
      package: package(),
      source_url: "https://github.com/warmwaffles/exqlite",
      start_permanent: Mix.env() == :prod,
      test_paths: test_paths(),
      version: "0.1.1"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:db_connection, "~> 2.1"},
      {:decimal, "~> 2.0"},
      {:ecto_sql, "~> 3.5.4"},
      {:elixir_make, "~> 0.6", runtime: false},
      {:ex_doc, "~> 0.23.0", only: [:dev], runtime: false},
      {:jason, ">= 0.0.0", only: [:test, :docs]},
      {:temp, "~> 0.4", only: [:test]}
    ]
  end

  defp description do
    "An Sqlite3 Elixir library."
  end

  defp package do
    [
      name: "exqlite",
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/warmwaffles/exqlite",
        "docs" => "https://hexdocs.pm/exqlite"
      }
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp test_paths, do: ["test"]
end
