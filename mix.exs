defmodule Exqlite.MixProject do
  use Mix.Project

  @version "1.0.0-rc.0"
  @sqlite_version "3.46.1"

  def project do
    [
      app: :exqlite,
      version: @version,
      elixir: "~> 1.14",
      compilers: [:elixir_make] ++ Mix.compilers(),
      make_targets: ["all"],
      make_clean: ["clean"],
      make_force_build: Application.get_env(:exqlite, :force_build, false),
      make_precompiler: make_precompiler(),
      make_precompiler_url:
        "https://github.com/elixir-sqlite/exqlite/releases/download/v#{@version}/@{artefact_filename}",
      make_precompiler_filename: "sqlite3_nif",
      make_precompiler_nif_versions: make_precompiler_nif_versions(),
      make_env: Application.get_env(:exqlite, :make_env, %{}),
      cc_precompiler: cc_precompiler(),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      package: package(),
      description: description(),
      elixirc_paths: elixirc_paths(Mix.env()),
      dialyzer: dialyzer(),
      test_coverage: [
        # TODO
        ignore_modules: [
          Exqlite.Nif,
          Mix.Tasks.DownloadSqlite,
          Mix.Tasks.TestSqliteVersion
        ]
      ],

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

  def sqlite_version, do: @sqlite_version

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_sqlean, "~> 0.8.5", only: [:dev, :test]},
      {:elixir_make, "~> 0.8", runtime: false},
      {:cc_precompiler, "~> 0.1", runtime: false},
      {:ex_doc, "~> 0.27", only: :dev, runtime: false},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.3.0", only: [:dev, :test], runtime: false},
      {:benchee, "~> 1.3", only: :bench}
    ]
  end

  defp aliases do
    [
      lint: ["format --check-formatted", "credo --all", "dialyzer"]
    ]
  end

  defp description do
    "An Elixir SQLite3 library"
  end

  defp make_precompiler do
    if System.get_env("EXQLITE_USE_SYSTEM") != nil do
      nil
    else
      {:nif, CCPrecompiler}
    end
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
        checksum.exs
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

  defp dialyzer do
    [
      plt_add_deps: :apps_direct,
      plt_add_apps: ~w(table)a
    ]
  end

  def make_precompiler_nif_versions do
    [
      versions: ["2.16", "2.17"]
    ]
  end

  defp cc_precompiler do
    [
      cleanup: "clean",
      compilers: %{
        {:unix, :linux} => %{
          :include_default_ones => true,
          "x86_64-linux-musl" => "x86_64-linux-musl-",
          "aarch64-linux-musl" => "aarch64-linux-musl-",
          "riscv64-linux-musl" => "riscv64-linux-musl-",
          "x86_64-linux-gnu" => "x86_64-linux-gnu-",
          "aarch64-linux-gnu" => "aarch64-linux-gnu-",
          "riscv64-linux-gnu" => "riscv64-linux-gnu-"
        },
        {:unix, :darwin} => %{
          :include_default_ones => true
        },
        {:win32, :nt} => %{
          :include_default_ones => true
        }
      }
    ]
  end
end
