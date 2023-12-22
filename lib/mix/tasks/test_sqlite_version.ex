defmodule Mix.Tasks.TestSqliteVersion do
  @moduledoc false

  use Mix.Task

  @shortdoc "Tests that the SQLite amalgation version matches the SQLite version in mix.exs"
  def run(_args) do
    # Get mix SQLite version
    mix_version = Exqlite.MixProject.sqlite_version()

    # Get installed SQLite version
    {:ok, conn} = Exqlite.open(":memory:")

    {:ok, [[amalgamation_version]]} =
      Exqlite.prepare_fetch_all(conn, "select sqlite_version()")

    if mix_version != amalgamation_version do
      Mix.raise(
        "mix test_sqlite_version failed: the mix.exs version (#{mix_version}) " <>
          "does not match the amalgation version (#{amalgamation_version})"
      )
    end
  end
end
