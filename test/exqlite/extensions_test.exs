defmodule Exqlite.ExtensionsTest do
  use ExUnit.Case, async: true
  alias Exqlite.Sqlite3

  describe "enable_load_extension" do
    setup do
      {:ok, conn} = Sqlite3.open(":memory:")
      on_exit(fn -> :ok = Sqlite3.close(conn) end)
      {:ok, conn: conn}
    end

    test "loading can be enabled / disabled", %{conn: conn} do
      assert :ok = Sqlite3.enable_load_extension(conn, true)

      assert {:ok, [[nil]]} =
               prepare_fetch_all(
                 conn,
                 "select load_extension(?)",
                 [ExSqlean.path_for("re")]
               )

      assert :ok = Sqlite3.enable_load_extension(conn, false)

      assert {:error, "not authorized"} =
               prepare_fetch_all(
                 conn,
                 "select load_extension(?)",
                 [ExSqlean.path_for("re")]
               )
    end

    test "works for 're' (regex)", %{conn: conn} do
      :ok = Sqlite3.enable_load_extension(conn, true)

      {:ok, _} =
        prepare_fetch_all(
          conn,
          "select load_extension(?)",
          [ExSqlean.path_for("re")]
        )

      assert {:ok, [[0]]} =
               prepare_fetch_all(
                 conn,
                 "select regexp_like('the year is 2021', ?)",
                 ["2k21"]
               )

      assert {:ok, [[1]]} =
               prepare_fetch_all(
                 conn,
                 "select regexp_like('the year is 2021', ?)",
                 ["2021"]
               )
    end

    test "stats extension", %{conn: conn} do
      :ok = Sqlite3.enable_load_extension(conn, true)

      for ext <- ["stats", "series"] do
        {:ok, _} =
          prepare_fetch_all(
            conn,
            "select load_extension(?)",
            [ExSqlean.path_for(ext)]
          )
      end

      assert {:ok, [[50.5]]} =
               prepare_fetch_all(
                 conn,
                 "select median(value) from generate_series(1, 100)"
               )
    end
  end

  defp prepare_fetch_all(conn, sql, args \\ []) do
    with {:ok, stmt} <- Sqlite3.prepare(conn, sql) do
      try do
        with :ok <- Sqlite3.bind(conn, stmt, args) do
          Sqlite3.fetch_all(conn, stmt)
        end
      after
        Sqlite3.release(conn, stmt)
      end
    end
  end
end
