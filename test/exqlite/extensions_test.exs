defmodule Exqlite.ExtensionsTest do
  use ExUnit.Case, async: true

  defp all(db, sql, args \\ []) do
    {:ok, stmt} = Exqlite.prepare(db, sql)
    on_exit(fn -> Exqlite.finalize(stmt) end)

    unless args == [] do
      :ok = Exqlite.bind_all(db, stmt, args)
    end

    Exqlite.fetch_all(db, stmt, 100)
  end

  describe "enable_load_extension" do
    setup do
      {:ok, db} = Exqlite.open(":memory:", [:readwrite])
      on_exit(fn -> :ok = Exqlite.close(db) end)
      {:ok, db: db}
    end

    test "loading can be enabled / disabled", %{db: db} do
      assert :ok = Exqlite.enable_load_extension(db, true)

      re = ExSqlean.path_for("re")

      assert {:ok, [[nil]]} = all(db, "select load_extension(?)", [re])

      assert :ok = Exqlite.enable_load_extension(db, false)

      assert {:error, %Exqlite.Error{code: 1, message: "not authorized"}} =
               all(db, "select load_extension(?)", [re])
    end

    test "works for 're' (regex)", %{db: db} do
      :ok = Exqlite.enable_load_extension(db, true)

      re = ExSqlean.path_for("re")
      {:ok, _} = all(db, "select load_extension(?)", [re])

      assert {:ok, [[0]]} =
               all(db, "select regexp_like('the year is 2021', ?)", ["2k21"])

      assert {:ok, [[1]]} =
               all(db, "select regexp_like('the year is 2021', ?)", ["2021"])
    end

    test "stats extension", %{db: db} do
      :ok = Exqlite.enable_load_extension(db, true)

      for ext <- ["stats", "series"] do
        {:ok, _} = all(db, "select load_extension(?)", [ExSqlean.path_for(ext)])
      end

      assert {:ok, [[50.5]]} =
               all(db, "select median(value) from generate_series(1, 100)")
    end
  end
end
