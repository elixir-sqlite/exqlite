defmodule ExqliteTest do
  use ExUnit.Case, case: :async

  defp all(db, sql, args \\ []) do
    with {:ok, stmt} <- Exqlite.prepare(db, sql) do
      try do
        with :ok <- Exqlite.bind_all(db, stmt, args) do
          Exqlite.fetch_all(db, stmt, 100)
        end
      after
        Exqlite.finalize(stmt)
      end
    end
  end

  describe ".open/2" do
    test "opens a database in memory" do
      assert {:ok, db} = Exqlite.open(":memory:", [:readonly])
      on_exit(fn -> Exqlite.close(db) end)
      assert is_reference(db)
    end

    @tag :tmp_dir
    test "opens a database on disk", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "db.sqlite")

      assert {:ok, db} = Exqlite.open(path, [:create, :readwrite])
      on_exit(fn -> Exqlite.close(db) end)
      assert is_reference(db)
    end

    @tag :tmp_dir
    test "creates database path on disk when non-existent", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "db.sqlite")
      if File.exists?(path), do: File.rm!(path)

      assert {:ok, db} = Exqlite.open(path, [:create, :readwrite])
      on_exit(fn -> Exqlite.close(db) end)

      assert is_reference(db)
      assert File.exists?(path)
    end

    @tag :tmp_dir
    test "connects to a file from URL", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "db.sqlite")

      assert {:ok, db} =
               Exqlite.open("file:#{path}?mode=rwc", [:uri, :create, :readwrite])

      on_exit(fn -> Exqlite.close(db) end)
      assert is_reference(db)
    end

    @tag :tmp_dir
    test "opens a database in readonly mode", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "db.sqlite")
      if File.exists?(path), do: File.rm!(path)

      # Create database with readwrite flag
      {:ok, rw} = Exqlite.open(path, [:create, :readwrite])
      on_exit(fn -> Exqlite.close(rw) end)

      :ok = Exqlite.execute(rw, "create table test (stuff text)")
      :ok = Exqlite.execute(rw, "insert into test (stuff) values ('This is a test')")

      # Read from a readonly database
      {:ok, ro} = Exqlite.open(path, [:readonly])
      on_exit(fn -> Exqlite.close(ro) end)
      {:ok, stmt} = Exqlite.prepare(ro, "select rowid, stuff from test")
      on_exit(fn -> Exqlite.finalize(stmt) end)

      assert {:row, [1, "This is a test"]} = Exqlite.step(ro, stmt)

      # Readonly database cannot insert
      assert {:error,
              %Exqlite.Error{code: 8, message: "attempt to write a readonly database"}} =
               Exqlite.execute(ro, "insert into test (stuff) values ('This is a test')")
    end

    @tag :tmp_dir
    test "connects to a file with an accented character", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "databasé.sqlite")
      assert {:ok, db} = Exqlite.open(path, [:create, :readwrite])
      on_exit(fn -> Exqlite.close(db) end)
      assert is_reference(db)
    end

    test "fails to open a database with invalid flag" do
      assert_raise ArgumentError, ~r/invalid flag/, fn ->
        Exqlite.open(":memory:", [:notarealflag])
      end
    end
  end

  describe ".close/1" do
    test "raises on invalid db handle" do
      db = make_ref()
      assert_raise ErlangError, ~r/invalid connection/, fn -> Exqlite.close(db) end
    end

    test "closes a database in memory" do
      {:ok, db} = Exqlite.open(":memory:", [:readwrite])
      assert :ok = Exqlite.close(db)
    end

    test "closing a database multiple times works" do
      {:ok, db} = Exqlite.open(":memory:", [:readwrite])
      assert :ok = Exqlite.close(db)
      assert :ok = Exqlite.close(db)
    end
  end

  describe ".execute/2" do
    setup do
      {:ok, db} = Exqlite.open(":memory:", [:readwrite])
      on_exit(fn -> Exqlite.close(db) end)
      {:ok, db: db}
    end

    test "creates a table", %{db: db} do
      assert :ok = Exqlite.execute(db, "create table test(stuff text)")
      assert :ok = Exqlite.execute(db, "insert into test(stuff) values('test')")
      assert {:ok, 1} = Exqlite.last_insert_rowid(db)
      assert {:ok, 1} = Exqlite.changes(db)
      assert {:ok, [[1, "test"]]} = all(db, "select rowid, stuff from test")
    end

    test "handles incorrect syntax", %{db: db} do
      assert {:error, %Exqlite.Error{code: 1, message: "near \"a\": syntax error"}} =
               Exqlite.execute(db, "create a dumb table test(stuff text)")

      assert {:ok, 0} = Exqlite.changes(db)
    end

    @tag :skip
    test "creates a virtual table with fts3", %{db: db} do
      assert :ok =
               Exqlite.execute(
                 db,
                 "create virtual table things using fts3(content text)"
               )

      assert :ok =
               Exqlite.execute(
                 db,
                 "insert into things(content) values('this is content')"
               )
    end

    @tag :skip
    test "creates a virtual table with fts4", %{db: db} do
      assert :ok =
               Exqlite.execute(
                 db,
                 "create virtual table things using fts4(content text)"
               )

      assert :ok =
               Exqlite.execute(
                 db,
                 "insert into things(content) values('this is content')"
               )
    end

    @tag :skip
    test "creates a virtual table with fts5", %{db: db} do
      assert :ok =
               Exqlite.execute(db, "create virtual table things using fts5(content)")

      assert :ok =
               Exqlite.execute(
                 db,
                 "insert into things(content) values('this is content')"
               )
    end

    test "handles unicode characters", %{db: db} do
      assert :ok = Exqlite.execute(db, "create table test (stuff text)")
      assert :ok = Exqlite.execute(db, "insert into test (stuff) values ('😝')")
      assert {:ok, [[1, "😝"]]} = all(db, "select rowid, stuff from test")
    end
  end

  describe ".prepare/2" do
    setup do
      {:ok, db} = Exqlite.open(":memory:", [:readwrite])
      on_exit(fn -> Exqlite.close(db) end)
      {:ok, db: db}
    end

    test "preparing a valid sql statement", %{db: db} do
      assert {:ok, stmt} = Exqlite.prepare(db, "select 1, 'hello'")
      on_exit(fn -> Exqlite.finalize(stmt) end)

      assert {:row, [1, "hello"]} = Exqlite.step(db, stmt)
      assert :done = Exqlite.step(db, stmt)
    end

    test "supports utf8 in error messages", %{db: db} do
      assert {:error, %Exqlite.Error{code: 1, message: "no such table: 🌍"} = error} =
               Exqlite.prepare(db, "select * from 🌍")

      assert Exception.message(error) == "no such table: 🌍"
    end
  end

  describe ".finalize/1" do
    setup do
      {:ok, db} = Exqlite.open(":memory:", [:readwrite])
      on_exit(fn -> Exqlite.close(db) end)
      {:ok, db: db}
    end

    test "releases a statement", %{db: db} do
      {:ok, stmt} = Exqlite.prepare(db, "select 1")

      assert :ok = Exqlite.finalize(stmt)

      # TODO improve SQLITE_MISUSE error message
      # https://www.sqlite.org/rescode.html#misuse
      assert {:error, %Exqlite.Error{code: 21, message: "not an error"}} =
               Exqlite.step(db, stmt)
    end

    test "double releasing a statement", %{db: db} do
      {:ok, stmt} = Exqlite.prepare(db, "select 1")
      assert :ok = Exqlite.finalize(stmt)
      assert :ok = Exqlite.finalize(stmt)
    end
  end

  describe ".bind_all/3" do
    setup do
      {:ok, db} = Exqlite.open(":memory:", [:readwrite])
      on_exit(fn -> Exqlite.close(db) end)
      {:ok, db: db}
    end

    test "binding values to a valid sql statement", %{db: db} do
      values = [1, "testing"]

      {:ok, stmt} = Exqlite.prepare(db, "select ?, ?")
      on_exit(fn -> Exqlite.finalize(stmt) end)

      assert :ok = Exqlite.bind_all(db, stmt, values)
      assert {:row, ^values} = Exqlite.step(db, stmt)
    end

    test "trying to bind with incorrect amount of arguments", %{db: db} do
      {:ok, stmt} = Exqlite.prepare(db, "select ?")
      on_exit(fn -> Exqlite.finalize(stmt) end)

      assert_raise ErlangError, ~r/arguments wrong length/, fn ->
        Exqlite.bind_all(db, stmt, [])
      end
    end
  end

  describe ".columns/2" do
    setup do
      {:ok, db} = Exqlite.open(":memory:", [:readwrite])
      on_exit(fn -> Exqlite.close(db) end)
      {:ok, db: db}
    end

    test "returns the column definitions", %{db: db} do
      {:ok, stmt} = Exqlite.prepare(db, "select 1 as id, 'hello' as stuff")
      on_exit(fn -> Exqlite.finalize(stmt) end)
      assert {:ok, ["id", "stuff"]} = Exqlite.columns(db, stmt)
    end

    test "supports utf8 column names", %{db: db} do
      {:ok, stmt} = Exqlite.prepare(db, "select 1 as 👋, 'hello' as ✍️")
      on_exit(fn -> Exqlite.finalize(stmt) end)
      assert {:ok, ["👋", "✍️"]} = Exqlite.columns(db, stmt)
    end
  end

  describe ".step/2" do
    setup do
      {:ok, db} = Exqlite.open(":memory:", [:readwrite])
      on_exit(fn -> Exqlite.close(db) end)
      {:ok, db: db}
    end

    test "returns results", %{db: db} do
      {:ok, stmt} = Exqlite.prepare(db, "select 1, 'test'")
      on_exit(fn -> Exqlite.finalize(stmt) end)

      assert {:row, [1, "test"]} = Exqlite.step(db, stmt)
      assert :done = Exqlite.step(db, stmt)

      assert {:row, [1, "test"]} = Exqlite.step(db, stmt)
      assert :done = Exqlite.step(db, stmt)
    end

    test "returns no results", %{db: db} do
      {:ok, stmt} = Exqlite.prepare(db, "select * from sqlite_master")
      on_exit(fn -> Exqlite.finalize(stmt) end)

      assert :done = Exqlite.step(db, stmt)
    end

    test "works with insert", %{db: db} do
      :ok = Exqlite.execute(db, "create table test(stuff text)")

      {:ok, stmt} = Exqlite.prepare(db, "insert into test(stuff) values(?1)")
      on_exit(fn -> Exqlite.finalize(stmt) end)

      :ok = Exqlite.bind_all(db, stmt, ["this is a test"])
      assert :done = Exqlite.step(db, stmt)

      assert {:ok, [[1, "this is a test"]]} = all(db, "select rowid, stuff from test")
    end
  end

  describe ".multi_step/3" do
    setup do
      {:ok, db} = Exqlite.open(":memory:", [:readwrite])
      on_exit(fn -> Exqlite.close(db) end)

      :ok = Exqlite.execute(db, "create table test(stuff text)")

      rows = [
        ["one"],
        ["two"],
        ["three"],
        ["four"],
        ["five"],
        ["six"]
      ]

      {:ok, insert} = Exqlite.prepare(db, "insert into test(stuff) values(?1)")
      :ok = Exqlite.insert_all(db, insert, rows)
      :ok = Exqlite.finalize(insert)

      {:ok, db: db}
    end

    test "returns results", %{db: db} do
      {:ok, stmt} = Exqlite.prepare(db, "select rowid, stuff from test order by rowid")
      on_exit(fn -> Exqlite.finalize(stmt) end)

      assert {:rows, rows} = Exqlite.multi_step(db, stmt, _steps = 4)
      assert rows == [[1, "one"], [2, "two"], [3, "three"], [4, "four"]]

      assert {:done, rows} = Exqlite.multi_step(db, stmt, _steps = 4)
      assert rows == [[5, "five"], [6, "six"]]
    end
  end

  # TODO move under .prepare
  describe "working with prepared statements after close" do
    test "returns proper error" do
      {:ok, db} = Exqlite.open(":memory:", [:readwrite])

      {:ok, stmt} = Exqlite.prepare(db, "select ?1")
      on_exit(fn -> Exqlite.finalize(stmt) end)

      :ok = Exqlite.close(db)
      :ok = Exqlite.bind_all(db, stmt, ["this is a test"])

      # TODO improve SQLITE_MISUSE error message
      assert {:error, %Exqlite.Error{code: 21, message: "out of memory"}} =
               Exqlite.execute(db, "select 1")

      assert {:row, ["this is a test"]} = Exqlite.step(db, stmt)
      assert :done = Exqlite.step(db, stmt)
    end
  end

  describe "serialize and deserialize" do
    @tag :tmp_dir
    test "serialize a database to binary and deserialize to new database", %{
      tmp_dir: tmp_dir
    } do
      path = Path.join(tmp_dir, "db.sqlite")
      if File.exists?(path), do: File.rm!(path)
      {:ok, db} = Exqlite.open(path, [:create, :readwrite])

      :ok = Exqlite.execute(db, "create table test(stuff text)")

      assert {:ok, binary} = Exqlite.serialize(db, "main")
      assert is_binary(binary)
      :ok = Exqlite.close(db)

      {:ok, db} = Exqlite.open(":memory:", [:readwrite])
      assert :ok = Exqlite.deserialize(db, "main", binary)

      :ok = Exqlite.execute(db, "insert into test(stuff) values('hello')")

      {:ok, stmt} = Exqlite.prepare(db, "select rowid, stuff from test")
      on_exit(fn -> Exqlite.finalize(stmt) end)

      assert {:row, [1, "hello"]} = Exqlite.step(db, stmt)
    end
  end

  describe "set_update_hook/2" do
    defmodule ChangeListener do
      use GenServer

      def start_link({parent, name}),
        do: GenServer.start_link(__MODULE__, {parent, name})

      def init({parent, name}), do: {:ok, {parent, name}}

      def handle_info({_action, _db, _table, _row_id} = change, {parent, name}) do
        send(parent, {change, name})
        {:noreply, {parent, name}}
      end
    end

    @describetag :tmp_dir

    setup %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "db.sqlite")

      {:ok, db} = Exqlite.open(path, [:create, :readwrite])
      on_exit(fn -> Exqlite.close(db) end)

      :ok = Exqlite.execute(db, "create table test(num integer)")
      {:ok, db: db, path: path}
    end

    test "can listen to data change notifications", context do
      {:ok, listener_pid} = ChangeListener.start_link({self(), :listener})
      Exqlite.set_update_hook(context.db, listener_pid)

      :ok = Exqlite.execute(context.db, "insert into test(num) values (10)")
      :ok = Exqlite.execute(context.db, "insert into test(num) values (11)")
      :ok = Exqlite.execute(context.db, "update test set num = 1000")
      :ok = Exqlite.execute(context.db, "delete from test where num = 1000")

      assert_receive {{:insert, "main", "test", 1}, _}, 1000
      assert_receive {{:insert, "main", "test", 2}, _}, 1000
      assert_receive {{:update, "main", "test", 1}, _}, 1000
      assert_receive {{:update, "main", "test", 2}, _}, 1000
      assert_receive {{:delete, "main", "test", 1}, _}, 1000
      assert_receive {{:delete, "main", "test", 2}, _}, 1000
    end

    test "only one pid can listen at a time", context do
      {:ok, listener1_pid} = ChangeListener.start_link({self(), :listener1})
      {:ok, listener2_pid} = ChangeListener.start_link({self(), :listener2})

      Exqlite.set_update_hook(context.db, listener1_pid)
      :ok = Exqlite.execute(context.db, "insert into test(num) values (10)")
      assert_receive {{:insert, "main", "test", 1}, :listener1}, 1000

      Exqlite.set_update_hook(context.db, listener2_pid)
      :ok = Exqlite.execute(context.db, "insert into test(num) values (10)")
      assert_receive {{:insert, "main", "test", 2}, :listener2}, 1000
      refute_receive {{:insert, "main", "test", 2}, :listener1}, 1000
    end

    test "notifications don't cross dbs", context do
      {:ok, listener_pid} = ChangeListener.start_link({self(), :listener})
      {:ok, new_db} = Exqlite.open(context.path, [:readwrite])
      Exqlite.set_update_hook(new_db, listener_pid)
      :ok = Exqlite.execute(context.db, "insert into test(num) values (10)")
      refute_receive {{:insert, "main", "test", 1}, _}, 1000
    end
  end

  describe "set_log_hook/1" do
    setup do
      {:ok, db} = Exqlite.open(":memory:", [:readwrite])
      on_exit(fn -> Exqlite.close(db) end)
      {:ok, db: db}
    end

    test "can receive errors", %{db: db} do
      assert :ok = Exqlite.set_log_hook(self())

      assert {:error, %Exqlite.Error{code: 1, message: "near \"some\": syntax error"}} =
               Exqlite.prepare(db, "some invalid sql")

      assert_receive {:log, rc, msg}
      assert rc == 1
      assert msg == "near \"some\": syntax error in \"some invalid sql\""
      refute_receive _anything_else
    end

    test "only one pid can listen at a time", %{db: db} do
      assert :ok = Exqlite.set_log_hook(self())

      task =
        Task.async(fn ->
          :ok = Exqlite.set_log_hook(self())

          assert {:error,
                  %Exqlite.Error{code: 1, message: "near \"some\": syntax error"}} =
                   Exqlite.prepare(db, "some invalid sql")

          assert_receive {:log, rc, msg}
          assert rc == 1
          assert msg == "near \"some\": syntax error in \"some invalid sql\""
          refute_receive _anything_else
        end)

      Task.await(task)
      refute_receive _anything_else
    end

    test "receives notifications from all dbs", %{db: db1} do
      assert :ok = Exqlite.set_log_hook(self())

      assert {:ok, db2} = Exqlite.open(":memory:", [:readwrite])
      on_exit(fn -> Exqlite.close(db2) end)

      assert {:error, _reason} = Exqlite.prepare(db1, "some invalid sql 1")
      assert_receive {:log, rc, msg}
      assert rc == 1
      assert msg == "near \"some\": syntax error in \"some invalid sql 1\""
      refute_receive _anything_else

      assert {:error, _reason} = Exqlite.prepare(db2, "some invalid sql 2")
      assert_receive {:log, rc, msg}
      assert rc == 1
      assert msg == "near \"some\": syntax error in \"some invalid sql 2\""
      refute_receive _anything_else
    end
  end

  describe ".interrupt/1" do
    setup do
      {:ok, db} = Exqlite.open(":memory:", [:readwrite])
      on_exit(fn -> Exqlite.close(db) end)
      {:ok, db: db}
    end

    test "double interrupting a db", %{db: db} do
      assert :ok = Exqlite.interrupt(db)
      assert :ok = Exqlite.interrupt(db)
    end

    test "interrupting a long running query and able to close a db", %{db: db} do
      test = self()

      spawn(fn ->
        assert {:error, %Exqlite.Error{code: 9, message: "interrupted"}} =
                 all(db, """
                 WITH RECURSIVE r(i) AS (
                   VALUES(0) UNION ALL SELECT i FROM r LIMIT 1000000000
                 )
                 SELECT i FROM r WHERE i = 1
                 """)

        send(test, :done)
      end)

      Process.sleep(100)
      assert :ok = Exqlite.interrupt(db)
      assert {:ok, [[1]]} = all(db, "select 1")

      assert_receive :done
    end
  end
end
