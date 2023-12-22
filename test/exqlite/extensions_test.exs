defmodule Exqlite.ExtensionsTest do
  use ExUnit.Case, async: true

  describe "enable_load_extension" do
    setup do
      {:ok, conn} = Exqlite.open(":memory:")
      on_exit(fn -> :ok = Exqlite.close(conn) end)
      {:ok, conn: conn}
    end

    test "loading can be enabled / disabled", %{conn: conn} do
      assert :ok = Exqlite.enable_load_extension(conn)

      assert {:ok, [[nil]]} =
               Exqlite.prepare_fetch_all(
                 conn,
                 "select load_extension(?)",
                 [ExSqlean.path_for("re")]
               )

      assert :ok = Exqlite.disable_load_extension(conn)

      assert {:error, %Exqlite.Error{message: "not authorized"}} =
               Exqlite.prepare_fetch_all(
                 conn,
                 "select load_extension(?)",
                 [ExSqlean.path_for("re")]
               )
    end

    test "works for 're' (regex)", %{conn: conn} do
      :ok = Exqlite.enable_load_extension(conn)

      {:ok, _} =
        Exqlite.prepare_fetch_all(
          conn,
          "select load_extension(?)",
          [ExSqlean.path_for("re")]
        )

      assert {:ok, [[0]]} =
               Exqlite.prepare_fetch_all(
                 conn,
                 "select regexp_like('the year is 2021', ?)",
                 ["2k21"]
               )

      assert {:ok, [[1]]} =
               Exqlite.prepare_fetch_all(
                 conn,
                 "select regexp_like('the year is 2021', ?)",
                 ["2021"]
               )
    end

    test "stats extension", %{conn: conn} do
      :ok = Exqlite.enable_load_extension(conn)

      for ext <- ["stats", "series"] do
        {:ok, _} =
          Exqlite.prepare_fetch_all(
            conn,
            "select load_extension(?)",
            [ExSqlean.path_for(ext)]
          )
      end

      assert {:ok, [[50.5]]} =
               Exqlite.prepare_fetch_all(
                 conn,
                 "select median(value) from generate_series(1, 100)"
               )
    end
  end
end
