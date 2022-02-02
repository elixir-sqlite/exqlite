defmodule Exqlite.MixProject do
  use Mix.Project

  @version "0.9.3"

  def project do
    [
      app: :exqlite,
      version: @version,
      elixir: "~> 1.10",
      compilers: [:elixir_make] ++ Mix.compilers(),
      make_targets: ["all"],
      make_clean: ["clean"],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      description: description(),
      test_paths: test_paths(System.get_env("EXQLITE_INTEGRATION")),
      elixirc_paths: elixirc_paths(Mix.env()),

      # Docs
      name: "Exqlite",
      source_url: "https://github.com/elixir-sqlite/exqlite",
      homepage_url: "https://github.com/elixir-sqlite/exqlite",
      docs: docs()
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
      {:ex_sqlean, "~> 0.8.5", only: [:dev, :test]},
      {:elixir_make, "~> 0.6", runtime: false},
      {:ex_doc, "~> 0.27", only: :dev, runtime: false},
      {:temp, "~> 0.4", only: [:dev, :test]},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "An Elixir SQLite3 library"
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
      ),
      name: "exqlite",
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/elixir-sqlite/exqlite",
        "Changelog" => "https://github.com/elixir-sqlite/exqlite/blob/main/CHANGELOG.md"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: docs_extras(),
      source_ref: "v#{@version}",
      source_url: "https://github.com/elixir-sqlite/exqlite"
    ]
  end

  defp docs_extras do
    [
      "README.md": [title: "Readme"],
      "guides/windows.md": [],
      "CHANGELOG.md": []
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp test_paths(nil), do: ["test"]
  defp test_paths(_any), do: ["integration_test/exqlite"]
end
