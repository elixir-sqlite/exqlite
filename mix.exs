defmodule Exqlite.MixProject do
  use Mix.Project

  def project do
    [
      app: :exqlite,
      version: "0.5.0",
      elixir: "~> 1.8",
      compilers: [:elixir_make] ++ Mix.compilers(),
      make_targets: ["all"],
      make_clean: ["clean"],
      start_permanent: Mix.env() == :prod,
      source_url: "https://github.com/warmwaffles/exqlite",
      homepage_url: "https://github.com/warmwaffles/exqlite",
      deps: deps(),
      package: package(),
      description: description(),
      test_paths: test_paths(System.get_env("EXQLITE_INTEGRATION")),
      elixirc_paths: elixirc_paths(Mix.env())
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
      {:elixir_make, "~> 0.6", runtime: false},
      {:ex_doc, "~> 0.23.0", only: [:dev], runtime: false},
      {:jason, ">= 0.0.0", only: [:test, :docs]},
      {:temp, "~> 0.4", only: [:test]},
    ]
  end

  defp description do
    "An SQLite3 Elixir library with adapter for Ecto3."
  end

  defp package do
    [
      files: ~w(
        lib
        .formatter.exs
        mix.exs
        README.md
        LICENSE
        .clang-format
        c_src
        Makefile*
        sqlite3
      ),
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

  defp test_paths(nil), do: ["test"]
  defp test_paths(_any), do: ["integration_test/exqlite"]
end
