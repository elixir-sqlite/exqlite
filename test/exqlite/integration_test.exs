defmodule Exqlite.IntegrationTest do
  use ExUnit.Case, async: true

  setup do
    path =
      Path.join([
        System.tmp_dir!(),
        "exqlite_test_#{:os.system_time(:second)}_#{System.unique_integer([:positive])}.db"
      ])

    on_exit(fn ->
      Enum.each([path, path <> "-wal", path <> "-shm"], &File.rm/1)
    end)

    {:ok, path: path}
  end

  test "simple prepare, bind, step", %{path: path} do
    {:ok, conn} = Exqlite.open(path)
    on_exit(fn -> :ok = Exqlite.close(conn) end)

    :ok =
      Exqlite.execute(
        conn,
        "create table test (id integer primary key, stuff text) strict"
      )

    assert {:ok, stmt} =
             Exqlite.prepare(
               conn,
               "select type, name, sql from sqlite_master where tbl_name = ?"
             )

    on_exit(fn -> :ok = Exqlite.release(stmt) end)

    assert :ok = Exqlite.bind(conn, stmt, ["test"])

    assert {:row,
            [
              "table",
              "test",
              "CREATE TABLE test (id integer primary key, stuff text) strict"
            ]} =
             Exqlite.step(conn, stmt)

    assert :done = Exqlite.step(conn, stmt)
  end

  test "simple insert_all and fetch_all", %{path: path} do
    {:ok, conn} = Exqlite.open(path)
    on_exit(fn -> :ok = Exqlite.close(conn) end)

    :ok =
      Exqlite.execute(
        conn,
        "create table test (id integer primary key, stuff text) strict"
      )

    # TODO
    # assert :ok =
    #          Exqlite.prepare_insert_all(
    #            conn,
    #            "insert into test(id, stuff) values (?, ?)",
    #            [[1, "1"], [2, "2"], [3, "3"]]
    #          )

    {:ok, stmt} =
      Exqlite.prepare(conn, "insert into test(id,stuff) values(?,?),(?,?),(?,?)")

    :ok = Exqlite.bind(conn, stmt, [1, "1", 2, "2", 3, "3"])
    :done = Exqlite.step(conn, stmt)
    :ok = Exqlite.release(stmt)

    assert {:ok, [[1, "1"], [2, "2"], [3, "3"]]} =
             Exqlite.prepare_fetch_all(conn, "select * from test")

    # TODO
    # assert :ok =
    #          Exqlite.prepare_insert_all(
    #            conn,
    #            "insert into test(stuff, id) values (?, ?)",
    #            [["4", 4], ["5", 5]]
    #          )

    {:ok, stmt} = Exqlite.prepare(conn, "insert into test(id,stuff) values(?,?),(?,?)")
    :ok = Exqlite.bind(conn, stmt, [4, "4", 5, "5"])
    :done = Exqlite.step(conn, stmt)
    :ok = Exqlite.release(stmt)

    assert {:ok, [[4, "4"], [5, "5"]]} =
             Exqlite.prepare_fetch_all(conn, "select * from test where id > ?", [3])
  end

  test "consecutive transactions", %{path: path} do
    {:ok, conn1} = Exqlite.open(path)
    on_exit(fn -> :ok = Exqlite.close(conn1) end)
    :ok = Exqlite.execute(conn1, "pragma journal_mode=wal")
    {:ok, conn2} = Exqlite.open(path)
    on_exit(fn -> :ok = Exqlite.close(conn2) end)

    :ok = Exqlite.execute(conn1, "begin")
    assert {:ok, :transaction} = Exqlite.transaction_status(conn1)
    :ok = Exqlite.execute(conn1, "create table foo(id integer, val integer)")
    :ok = Exqlite.execute(conn1, "rollback")
    assert {:ok, :idle} = Exqlite.transaction_status(conn1)

    :ok = Exqlite.execute(conn2, "begin")
    assert {:ok, :transaction} = Exqlite.transaction_status(conn2)
    :ok = Exqlite.execute(conn2, "create table foo(id integer, val integer)")
    :ok = Exqlite.execute(conn2, "rollback")
    assert {:ok, :idle} = Exqlite.transaction_status(conn2)
  end

  test "write lock", %{path: path} do
    {:ok, conn1} = Exqlite.open(path)
    on_exit(fn -> :ok = Exqlite.close(conn1) end)

    :ok = Exqlite.execute(conn1, "pragma journal_mode=wal")
    :ok = Exqlite.execute(conn1, "pragma busy_timeout=0")

    {:ok, conn2} = Exqlite.open(path)
    on_exit(fn -> :ok = Exqlite.close(conn2) end)

    :ok = Exqlite.execute(conn1, "begin immediate")
    assert {:ok, :transaction} = Exqlite.transaction_status(conn1)

    assert {:error, %Exqlite.SQLiteError{rc: 5} = error} =
             Exqlite.execute(conn2, "begin immediate")

    assert error.message == "database is locked"
    assert Exception.message(error) == "database is locked"

    assert {:ok, :idle} = Exqlite.transaction_status(conn2)

    :ok = Exqlite.execute(conn1, "commit")
    assert {:ok, :idle} = Exqlite.transaction_status(conn1)

    :ok = Exqlite.execute(conn2, "begin immediate")
    assert {:ok, :transaction} = Exqlite.transaction_status(conn2)
    :ok = Exqlite.execute(conn2, "commit")
    assert {:ok, :idle} = Exqlite.transaction_status(conn2)
  end

  test "overlapped immediate/deferred transactions", %{path: path} do
    {:ok, conn1} = Exqlite.open(path)
    on_exit(fn -> :ok = Exqlite.close(conn1) end)

    :ok = Exqlite.execute(conn1, "pragma journal_mode=wal")

    {:ok, conn2} = Exqlite.open(path)
    on_exit(fn -> :ok = Exqlite.close(conn2) end)

    :ok = Exqlite.execute(conn1, "begin immediate")
    :ok = Exqlite.execute(conn1, "create table foo(id integer, val integer)")

    # transaction overlap
    :ok = Exqlite.execute(conn2, "begin")
    assert {:ok, :transaction} = Exqlite.transaction_status(conn2)

    :ok = Exqlite.execute(conn1, "rollback")
    assert {:ok, :idle} = Exqlite.transaction_status(conn1)

    :ok = Exqlite.execute(conn2, "create table foo(id integer, val integer)")
    :ok = Exqlite.execute(conn2, "rollback")
    assert {:ok, :idle} = Exqlite.transaction_status(conn2)
  end

  test "transaction handling with single connection", %{path: path} do
    {:ok, conn} = Exqlite.open(path)
    on_exit(fn -> :ok = Exqlite.close(conn) end)
    :ok = Exqlite.execute(conn, "pragma journal_mode=wal")

    Enum.each(1..5, fn _ ->
      :ok = Exqlite.execute(conn, "begin")
      assert {:ok, :transaction} = Exqlite.transaction_status(conn)
      :ok = Exqlite.execute(conn, "create table foo(id integer, val integer)")
      :ok = Exqlite.execute(conn, "rollback")
      assert {:ok, :idle} = Exqlite.transaction_status(conn)
    end)
  end
end
