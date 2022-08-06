defmodule Mix.Tasks.CheckSqliteVersion do
  use Mix.Task

  @requirements ["app.start"]

  @shortdoc "Checks that the SQLite amalgation version matches the SQLite version in mix.exs"
  def run(_args) do
    # Get mix Sqlite version
    mix_version = Exqlite.MixProject.sqlite_version()

    # Get installed Sqlite version
    {:ok, conn} = Exqlite.Sqlite3.open(":memory:")
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "select sqlite_version()")
    {_, [amalgamation_version]} = Exqlite.Sqlite3.step(conn, stmt)

    if mix_version != amalgamation_version do
      "mix check_sqlite_version failed: the mix.exs version (#{mix_version}) " <>
      "does not match the amalgation version (#{amalgamation_version})"
      |> Mix.raise()
    end
  end
end