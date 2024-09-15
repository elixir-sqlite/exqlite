defmodule Exqlite.IntegrationTest do
  use ExUnit.Case, async: true

  describe "simple" do
    setup do
      {:ok, db} = Exqlite.open(":memory:", [:readwrite])
      on_exit(fn -> :ok = Exqlite.close(db) end)

      :ok =
        Exqlite.execute(db, "create table test (id ingeger primary key, stuff text)")

      {:ok, db: db}
    end

    test "prepare, bind, execute, and step", %{db: db} do
      assert :ok =
               Exqlite.execute(db, "insert into test (id, stuff) values (1, 'hello')")

      assert {:ok, stmt} =
               Exqlite.prepare(db, "select * from test where id = ?")

      on_exit(fn -> Exqlite.finalize(stmt) end)

      assert :ok = Exqlite.bind_all(db, stmt, [1])

      assert {:row, [1, "hello"]} = Exqlite.step(db, stmt)
      assert :done = Exqlite.step(db, stmt)
    end

    test "insert_all and fetch_all", %{db: db} do
      {:ok, insert} = Exqlite.prepare(db, "insert into test (id, stuff) values (?, ?)")
      on_exit(fn -> Exqlite.finalize(insert) end)

      assert :ok = Exqlite.insert_all(db, insert, [[1, "hello"], [2, "world"]])

      {:ok, select} = Exqlite.prepare(db, "select * from test limit ?")
      on_exit(fn -> Exqlite.finalize(select) end)

      assert :ok = Exqlite.bind_all(db, select, [100])

      assert {:ok, [[1, "hello"], [2, "world"]]} =
               Exqlite.fetch_all(db, select, _steps = 100)
    end
  end

  describe "locks" do
    @describetag :tmp_dir

    setup %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "db.sqlite")
      if File.exists?(path), do: File.rm!(path)

      {:ok, db1} = Exqlite.open(path, [:create, :readwrite])
      on_exit(fn -> Exqlite.close(db1) end)

      {:ok, db2} = Exqlite.open(path, [:readwrite])
      on_exit(fn -> Exqlite.close(db2) end)

      {:ok, dbs: [db1, db2]}
    end

    test "consecutive transactions", %{dbs: [db1, db2]} do
      assert :ok = Exqlite.execute(db1, "begin")
      assert :transaction = Exqlite.transaction_status(db1)
      assert :ok = Exqlite.execute(db1, "create table foo(id integer, val integer)")
      assert :ok = Exqlite.execute(db1, "rollback")
      assert :idle = Exqlite.transaction_status(db1)

      assert :ok = Exqlite.execute(db2, "begin")
      assert :transaction = Exqlite.transaction_status(db2)
      assert :ok = Exqlite.execute(db2, "create table foo(id integer, val integer)")
      assert :ok = Exqlite.execute(db2, "rollback")
      assert :idle = Exqlite.transaction_status(db2)
    end

    test "write lock", %{dbs: [db1, db2]} do
      :ok = Exqlite.execute(db2, "pragma busy_timeout=0")

      assert :ok = Exqlite.execute(db1, "begin immediate")
      assert :transaction = Exqlite.transaction_status(db1)

      # https://www.sqlite.org/rescode.html#busy
      assert {:error, %Exqlite.Error{code: 5, message: "database is locked"}} =
               Exqlite.execute(db2, "begin immediate")

      assert :idle = Exqlite.transaction_status(db2)

      assert :ok = Exqlite.execute(db1, "commit")
      assert :idle = Exqlite.transaction_status(db1)

      assert :ok = Exqlite.execute(db2, "begin immediate")
      assert :transaction = Exqlite.transaction_status(db2)
      assert :ok = Exqlite.execute(db2, "commit")
      assert :idle = Exqlite.transaction_status(db2)
    end

    test "overlapped immediate/deferred transactions", %{dbs: [db1, db2]} do
      assert :ok = Exqlite.execute(db1, "begin immediate")
      assert :ok = Exqlite.execute(db1, "create table foo(id integer, val integer)")

      # transaction overlap
      assert :ok = Exqlite.execute(db2, "begin")
      assert :transaction = Exqlite.transaction_status(db2)

      assert :ok = Exqlite.execute(db1, "rollback")
      assert :idle = Exqlite.transaction_status(db1)

      assert :ok = Exqlite.execute(db2, "create table foo(id integer, val integer)")
      assert :ok = Exqlite.execute(db2, "rollback")
      assert :idle = Exqlite.transaction_status(db2)
    end

    test "transaction handling with single db", %{dbs: [db1, _db2]} do
      assert :ok = Exqlite.execute(db1, "begin")
      assert :transaction = Exqlite.transaction_status(db1)
      assert :ok = Exqlite.execute(db1, "create table foo(id integer, val integer)")
      assert :ok = Exqlite.execute(db1, "rollback")
      assert :idle = Exqlite.transaction_status(db1)
      assert :ok = Exqlite.execute(db1, "begin")
      assert :transaction = Exqlite.transaction_status(db1)
      assert :ok = Exqlite.execute(db1, "create table foo(id integer, val integer)")
      assert :ok = Exqlite.execute(db1, "rollback")
      assert :idle = Exqlite.transaction_status(db1)
    end
  end
end
