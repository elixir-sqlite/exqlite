defmodule Exqlite.PragmaTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "db.sqlite")
    if File.exists?(path), do: File.rm!(path)

    {:ok, db} = Exqlite.open(path, [:create, :readwrite])
    on_exit(fn -> :ok = Exqlite.close(db) end)

    {:ok, db: db}
  end

  defp one(db, sql) do
    {:ok, stmt} = Exqlite.prepare(db, sql)
    on_exit(fn -> Exqlite.finalize(stmt) end)
    {:ok, [row]} = Exqlite.fetch_all(db, stmt, 100)
    row
  end

  test "journal_mode", %{db: db} do
    assert [_default = "delete"] = one(db, "pragma journal_mode")

    for mode <- ["wal", "memory", "off", "delete", "truncate", "persist"] do
      :ok = Exqlite.execute(db, "pragma journal_mode=#{mode}")
      assert [^mode] = one(db, "pragma journal_mode")
    end
  end

  test "temp_store", %{db: db} do
    assert [_default = 0] = one(db, "pragma temp_store")

    for {name, code} <- [{"memory", 2}, {"default", 0}, {"file", 1}] do
      :ok = Exqlite.execute(db, "pragma temp_store=#{name}")
      assert [^code] = one(db, "pragma temp_store")
    end
  end

  test "synchronous", %{db: db} do
    assert [_full = 2] = one(db, "pragma synchronous")

    for {name, code} <- [{"extra", 3}, {"off", 0}, {"full", 2}, {"normal", 1}] do
      :ok = Exqlite.execute(db, "pragma synchronous=#{name}")
      assert [^code] = one(db, "pragma synchronous")
    end
  end

  test "foreign_keys", %{db: db} do
    assert [_off = 0] = one(db, "pragma foreign_keys")

    for {name, code} <- [{"on", 1}, {"off", 0}] do
      :ok = Exqlite.execute(db, "pragma foreign_keys=#{name}")
      assert [^code] = one(db, "pragma foreign_keys")
    end
  end

  test "cache_size", %{db: db} do
    assert [_default = -2000] = one(db, "pragma cache_size")
    :ok = Exqlite.execute(db, "pragma cache_size=-64000")
    assert [-64000] = one(db, "pragma cache_size")
  end
end
