defmodule Mix.Tasks.TestSqliteVersion do
  @moduledoc false

  use Mix.Task

  @shortdoc "Tests that the SQLite amalgation version matches the SQLite version in mix.exs"
  def run(_args) do
    # Get mix SQLite version
    mix_version = Exqlite.MixProject.sqlite_version()

    # Get installed SQLite version
    {:ok, [[amalgamation_version]]} =
      with_db(fn db -> all(db, "select sqlite_version()") end)

    if mix_version != amalgamation_version do
      ("mix test_sqlite_version failed: the mix.exs version (#{mix_version}) " <>
         "does not match the amalgation version (#{amalgamation_version})")
      |> Mix.raise()
    end
  end

  defp with_db(f) do
    with {:ok, db} <- Exqlite.open(":memory:", [:readonly]) do
      try do
        f.(db)
      after
        Exqlite.close(db)
      end
    end
  end

  defp all(db, sql) do
    with {:ok, stmt} <- Exqlite.prepare(db, sql) do
      try do
        Exqlite.fetch_all(db, stmt, _steps = 100)
      after
        Exqlite.finalize(stmt)
      end
    end
  end
end
