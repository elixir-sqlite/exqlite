defmodule ExqliteTest do
  use ExUnit.Case, async: true

  defp tmp_path do
    path =
      Path.join([
        System.tmp_dir!(),
        "exqlite_test_#{:os.system_time(:second)}_#{System.unique_integer([:positive])}.db"
      ])

    on_exit(fn ->
      Enum.each([path, path <> "-wal", path <> "-shm"], &File.rm/1)
    end)

    path
  end

  describe ".open/2" do
    test "opens a database in memory" do
      assert {:ok, conn} = Exqlite.open(":memory:")
      on_exit(fn -> :ok = Exqlite.close(conn) end)
      assert is_reference(conn)
    end

    test "opens a database on disk" do
      assert {:ok, conn} = Exqlite.open(tmp_path())
      on_exit(fn -> :ok = Exqlite.close(conn) end)
      assert is_reference(conn)
    end

    test "creates database path on disk when non-existent" do
      path = tmp_path()
      refute File.exists?(path)

      assert {:ok, conn} = Exqlite.open(path)
      on_exit(fn -> :ok = Exqlite.close(conn) end)

      assert is_reference(conn)
      assert File.exists?(path)
    end

    test "connects to a file from URL" do
      assert {:ok, conn} =
               Exqlite.open("file:#{tmp_path()}?mode=rwc", [:uri, :create, :readwrite])

      on_exit(fn -> :ok = Exqlite.close(conn) end)
      assert {:ok, [[1]]} = Exqlite.prepare_fetch_all(conn, "select 1")
    end

    test "opens a database in readonly mode" do
      path = tmp_path()

      {:ok, conn} = Exqlite.open(path)

      :ok =
        Exqlite.execute(conn, "create table test (id integer primary key, stuff text)")

      :ok = Exqlite.execute(conn, "insert into test (stuff) values ('This is a test')")
      :ok = Exqlite.close(conn)

      assert {:ok, conn} = Exqlite.open(path, [:readonly])
      on_exit(fn -> :ok = Exqlite.close(conn) end)

      assert {:ok, [[1, "This is a test"]]} =
               Exqlite.prepare_fetch_all(
                 conn,
                 "select id, stuff from test order by id asc"
               )

      assert {:error, %Exqlite.SQLiteError{} = error} =
               Exqlite.execute(
                 conn,
                 "insert into test (stuff) values ('This is a test')"
               )

      assert error.rc == 8
      assert error.message == "attempt to write a readonly database"

      assert Exception.message(error) ==
               "attempt to write a readonly database"
    end

    test "opens a URL" do
      path = tmp_path()

      assert {:ok, conn} =
               Exqlite.open("file:#{path}?mode=rwc", [:uri, :create, :readwrite])

      :ok = Exqlite.execute(conn, "create table test(col text) strict")
      :ok = Exqlite.close(conn)

      assert {:ok, conn} = Exqlite.open("file:#{path}?mode=ro", [:uri, :readonly])
      on_exit(fn -> :ok = Exqlite.close(conn) end)

      assert {:ok, []} = Exqlite.prepare_fetch_all(conn, "select * from test")

      assert {:ok, [["CREATE TABLE test(col text) strict"]]} =
               Exqlite.prepare_fetch_all(
                 conn,
                 "select sql from sqlite_master where name=?",
                 ["test"]
               )

      # TODO
      # assert {:error, %Exqlite.Error{} = error} =
      #          Exqlite.prepare_insert_all(
      #            conn,
      #            "insert into test(col) values (?)",
      #            [["something"]]
      #          )

      {:ok, stmt} = Exqlite.prepare(conn, "insert into test(col) values(?)")
      :ok = Exqlite.bind(conn, stmt, ["something"])

      {:error, %Exqlite.SQLiteError{} = error} = Exqlite.step(conn, stmt)
      assert error.rc == 8
      assert error.message == "attempt to write a readonly database"
    end

    test "fails to open a database with invalid flags" do
      assert_raise FunctionClauseError, fn ->
        Exqlite.open(tmp_path(), [:notaflag])
      end
    end
  end

  describe ".close/2" do
    test "doesn't crash on invalid conn handle" do
      conn = make_ref()
      assert {:error, %Exqlite.UsageError{} = error} = Exqlite.close(conn)
      assert error.message == :invalid_connection
    end

    test "closes an open database" do
      {:ok, conn} = Exqlite.open(tmp_path())
      assert :ok == Exqlite.close(conn)
      assert :ok == Exqlite.close(conn)
    end

    test "closes a database in memory" do
      {:ok, conn} = Exqlite.open(":memory:")
      assert :ok = Exqlite.close(conn)
    end

    test "closing a database multiple times works properly" do
      {:ok, conn} = Exqlite.open(":memory:")
      assert :ok = Exqlite.close(conn)
      assert :ok = Exqlite.close(conn)
    end
  end

  describe ".execute/2" do
    setup do
      {:ok, conn} = Exqlite.open(":memory:")
      on_exit(fn -> :ok = Exqlite.close(conn) end)
      {:ok, conn: conn}
    end

    test "creates a table", %{conn: conn} do
      assert :ok =
               Exqlite.execute(
                 conn,
                 "create table test (id integer primary key, stuff text)"
               )

      assert :ok =
               Exqlite.execute(
                 conn,
                 "insert into test (stuff) values ('This is a test')"
               )

      assert {:ok, 1} = Exqlite.last_insert_rowid(conn)
      assert {:ok, 1} = Exqlite.changes(conn)
    end

    test "handles incorrect syntax", %{conn: conn} do
      assert {:error, %Exqlite.SQLiteError{rc: 1, message: "SQL logic error"}} =
               Exqlite.execute(
                 conn,
                 "create a dumb table test (id integer primary key, stuff text)"
               )

      assert {:ok, 0} = Exqlite.changes(conn)
    end

    test "creates a virtual table with fts3", %{conn: conn} do
      assert :ok =
               Exqlite.execute(
                 conn,
                 "create virtual table things using fts3(content text)"
               )

      assert :ok =
               Exqlite.execute(
                 conn,
                 "insert into things(content) VALUES ('this is content')"
               )
    end

    test "creates a virtual table with fts4", %{conn: conn} do
      assert :ok =
               Exqlite.execute(
                 conn,
                 "create virtual table things using fts4(content text)"
               )

      assert :ok =
               Exqlite.execute(
                 conn,
                 "insert into things(content) VALUES ('this is content')"
               )
    end

    test "creates a virtual table with fts5", %{conn: conn} do
      assert :ok =
               Exqlite.execute(conn, "create virtual table things using fts5(content)")

      assert :ok =
               Exqlite.execute(
                 conn,
                 "insert into things(content) VALUES ('this is content')"
               )
    end

    test "handles unicode characters", %{conn: conn} do
      :ok =
        Exqlite.execute(conn, "create table test (id integer primary key, stuff text)")

      assert :ok = Exqlite.execute(conn, "insert into test (stuff) values ('😝')")
      assert {:ok, [[1, "😝"]]} = Exqlite.prepare_fetch_all(conn, "select * from test")
    end

    test "sets custom pragmas" do
      {:ok, conn} = Exqlite.open(tmp_path())
      on_exit(fn -> :ok = Exqlite.close(conn) end)

      :ok = Exqlite.execute(conn, "pragma checkpoint_fullfsync=0")
      {:ok, [[0]]} = Exqlite.prepare_fetch_all(conn, "pragma checkpoint_fullfsync")

      :ok = Exqlite.execute(conn, "pragma checkpoint_fullfsync=1")
      {:ok, [[1]]} = Exqlite.prepare_fetch_all(conn, "pragma checkpoint_fullfsync")
    end
  end

  describe ".prepare_fetch_all/4" do
    setup do
      {:ok, conn} = Exqlite.open(tmp_path())
      on_exit(fn -> :ok = Exqlite.close(conn) end)

      :ok = Exqlite.execute(conn, "pragma journal_mode=wal")

      :ok =
        Exqlite.execute(
          conn,
          "create table users (id integer primary key, name text) strict"
        )

      :ok = Exqlite.execute(conn, "insert into users (id, name) values (1, 'Jim')")
      :ok = Exqlite.execute(conn, "insert into users (id, name) values (2, 'Bob')")
      :ok = Exqlite.execute(conn, "insert into users (id, name) values (3, 'Dave')")
      :ok = Exqlite.execute(conn, "insert into users (id, name) values (4, 'Steve')")

      {:ok, conn: conn}
    end

    test "returns records", %{conn: conn} do
      assert {:ok, [[1, "Jim"], [2, "Bob"], [3, "Dave"]]} =
               Exqlite.prepare_fetch_all(conn, "select * from users where id < ?", [4])
    end

    test "returns correctly for empty result", %{conn: conn} do
      assert {:ok, []} =
               Exqlite.prepare_fetch_all(
                 conn,
                 "update users set name = ? where id = ?",
                 ["wow", 1]
               )

      assert {:ok, []} =
               Exqlite.prepare_fetch_all(
                 conn,
                 "update users set name = ? where id = ? returning *",
                 ["wow", 5]
               )

      assert {:ok, []} =
               Exqlite.prepare_fetch_all(conn, "select * from users where id > ?", [5])
    end

    @tag :skip
    test "returns timely and in order for big data sets", %{conn: conn} do
      :ok = Exqlite.execute(conn, "delete from users")

      users =
        Enum.map(1..10_000, fn i -> [i, "User-#{i}"] end)

      # TODO
      # :ok =
      #   Exqlite.prepare_insert_all(
      #     conn,
      #     "insert into users(id,name) values(?,?)",
      #     users
      #   )

      started_at = System.monotonic_time(:millisecond)
      assert {:ok, ^users} = Exqlite.prepare_fetch_all(conn, "select * from users")

      assert_in_delta started_at, System.monotonic_time(:millisecond), _ms = 50
    end
  end

  describe ".prepare/2" do
    setup do
      {:ok, conn} = Exqlite.open(":memory:")
      on_exit(fn -> :ok = Exqlite.close(conn) end)
      {:ok, conn: conn}
    end

    test "returns a prepared query", %{conn: conn} do
      :ok =
        Exqlite.execute(
          conn,
          "create table users (id integer primary key, name text) strict"
        )

      {:ok, stmt} = Exqlite.prepare(conn, "select * from users where id < ?")
      assert is_reference(stmt)
    end

    test "users table does not exist", %{conn: conn} do
      assert {:error, %Exqlite.SQLiteError{rc: 1} = error} =
               Exqlite.prepare(conn, "select * from users where id < ?")

      assert Exception.message(error) == "SQL logic error"
    end

    test "supports utf8 in error messages", %{conn: conn} do
      assert {:error, %Exqlite.SQLiteError{rc: 1, message: "SQL logic error"}} =
               Exqlite.prepare(conn, "select * from 🌍")
    end
  end

  describe ".step/2" do
    setup do
      {:ok, conn} = Exqlite.open(":memory:")
      on_exit(fn -> :ok = Exqlite.close(conn) end)

      :ok =
        Exqlite.execute(conn, "create table test (id integer primary key, stuff text)")

      {:ok, conn: conn}
    end

    test "returns results", %{conn: conn} do
      :ok = Exqlite.execute(conn, "insert into test (stuff) values ('This is a test')")
      {:ok, 1} = Exqlite.last_insert_rowid(conn)
      :ok = Exqlite.execute(conn, "insert into test (stuff) values ('Another test')")
      {:ok, 2} = Exqlite.last_insert_rowid(conn)

      {:ok, stmt} = Exqlite.prepare(conn, "select id, stuff from test order by id asc")
      on_exit(fn -> :ok = Exqlite.release(stmt) end)

      assert {:row, [1, "This is a test"]} = Exqlite.step(conn, stmt)
      assert {:row, [2, "Another test"]} = Exqlite.step(conn, stmt)
      assert :done = Exqlite.step(conn, stmt)

      assert {:row, [1, "This is a test"]} = Exqlite.step(conn, stmt)
      assert {:row, [2, "Another test"]} = Exqlite.step(conn, stmt)
      assert :done = Exqlite.step(conn, stmt)
    end

    test "returns no results", %{conn: conn} do
      {:ok, stmt} = Exqlite.prepare(conn, "select id, stuff from test")
      on_exit(fn -> :ok = Exqlite.release(stmt) end)
      assert :done = Exqlite.step(conn, stmt)
    end

    test "works with insert", %{conn: conn} do
      {:ok, stmt} = Exqlite.prepare(conn, "insert into test (stuff) values (?1)")
      on_exit(fn -> :ok = Exqlite.release(stmt) end)
      :ok = Exqlite.bind(conn, stmt, ["this is a test"])
      assert :done == Exqlite.step(conn, stmt)
    end
  end

  describe ".release/2" do
    setup do
      {:ok, conn} = Exqlite.open(tmp_path())
      on_exit(fn -> :ok = Exqlite.close(conn) end)
      {:ok, conn: conn}
    end

    test "releases the underlying prepared statement", %{conn: conn} do
      {:ok, stmt} = Exqlite.prepare(conn, "select * from sqlite_master")
      assert :ok = Exqlite.release(stmt)
      assert :ok = Exqlite.release(stmt)
    end

    test "releasing a nil statement" do
      assert {:error, %Exqlite.UsageError{message: :invalid_statement}} =
               Exqlite.release(nil)
    end
  end

  describe ".bind/3" do
    setup do
      {:ok, conn} = Exqlite.open(":memory:")
      on_exit(fn -> :ok = Exqlite.close(conn) end)

      :ok =
        Exqlite.execute(
          conn,
          "create table test (id integer primary key, stuff text)"
        )

      {:ok, stmt} = Exqlite.prepare(conn, "insert into test (stuff) values (?1)")
      on_exit(fn -> :ok = Exqlite.release(stmt) end)

      {:ok, conn: conn, stmt: stmt}
    end

    test "binding values to a valid sql statement", %{conn: conn, stmt: stmt} do
      assert :ok = Exqlite.bind(conn, stmt, ["testing"])
    end

    test "trying to bind with incorrect amount of arguments", %{conn: conn, stmt: stmt} do
      assert {:error, %Exqlite.UsageError{message: :arguments_wrong_length}} =
               Exqlite.bind(conn, stmt, [])
    end

    test "doesn't bind datetime value as string", %{conn: conn, stmt: stmt} do
      utc_now = ~U[2023-12-23 05:56:02.253039Z]

      assert {:error, %Exqlite.UsageError{} = error} =
               Exqlite.bind(conn, stmt, [utc_now])

      assert Exception.message(error) ==
               "unsupported type for bind: ~U[2023-12-23 05:56:02.253039Z]"
    end

    test "doesn't bind date value as string", %{conn: conn, stmt: stmt} do
      utc_today = Date.utc_today()

      assert {:error, %Exqlite.UsageError{} = error} =
               Exqlite.bind(conn, stmt, [utc_today])

      assert Exception.message(error) ==
               "unsupported type for bind: #{inspect(utc_today)}"
    end
  end

  describe ".columns/2" do
    setup do
      {:ok, conn} = Exqlite.open(":memory:")
      on_exit(fn -> :ok = Exqlite.close(conn) end)
      {:ok, conn: conn}
    end

    test "returns the column definitions", %{conn: conn} do
      :ok =
        Exqlite.execute(conn, "create table test (id integer primary key, stuff text)")

      {:ok, stmt} = Exqlite.prepare(conn, "select id, stuff from test")
      on_exit(fn -> :ok = Exqlite.release(stmt) end)

      assert {:ok, ["id", "stuff"]} = Exqlite.columns(conn, stmt)
    end

    test "supports utf8 column names", %{conn: conn} do
      :ok = Exqlite.execute(conn, "create table test(👋 text, ✍️ text)")
      {:ok, stmt} = Exqlite.prepare(conn, "select * from test")
      on_exit(fn -> :ok = Exqlite.release(stmt) end)
      assert {:ok, ["👋", "✍️"]} = Exqlite.columns(conn, stmt)
    end
  end

  describe ".multi_step/3" do
    test "returns results in batches" do
      {:ok, conn} = Exqlite.open(":memory:")
      on_exit(fn -> :ok = Exqlite.close(conn) end)

      :ok =
        Exqlite.execute(conn, "create table test (id integer primary key, stuff text)")

      :ok = Exqlite.execute(conn, "insert into test (stuff) values ('one')")
      :ok = Exqlite.execute(conn, "insert into test (stuff) values ('two')")
      :ok = Exqlite.execute(conn, "insert into test (stuff) values ('three')")
      :ok = Exqlite.execute(conn, "insert into test (stuff) values ('four')")
      :ok = Exqlite.execute(conn, "insert into test (stuff) values ('five')")
      :ok = Exqlite.execute(conn, "insert into test (stuff) values ('six')")

      assert {:ok, stmt} =
               Exqlite.prepare(conn, "select id, stuff from test order by id asc")

      on_exit(fn -> :ok = Exqlite.release(stmt) end)

      assert {:rows, [[1, "one"], [2, "two"], [3, "three"]]} =
               Exqlite.multi_step(conn, stmt, 3)

      assert {:rows, [[4, "four"], [5, "five"], [6, "six"]]} =
               Exqlite.multi_step(conn, stmt, 3)

      assert {:done, []} = Exqlite.multi_step(conn, stmt, 3)

      # stmt can be reusued afterwards
      assert {:done,
              [
                [1, "one"],
                [2, "two"],
                [3, "three"],
                [4, "four"],
                [5, "five"],
                [6, "six"]
              ]} = Exqlite.multi_step(conn, stmt, 7)
    end
  end

  describe "working with prepared statements after close" do
    test "returns proper error" do
      {:ok, conn} = Exqlite.open(":memory:")

      :ok =
        Exqlite.execute(conn, "create table test (id integer primary key, stuff text)")

      {:ok, stmt} = Exqlite.prepare(conn, "insert into test (stuff) values (?1)")
      :ok = Exqlite.close(conn)
      assert :ok = Exqlite.bind(conn, stmt, ["this is a test"])

      assert {:error, %Exqlite.SQLiteError{} = error} =
               Exqlite.execute(
                 conn,
                 "create table test (id integer primary key, stuff text)"
               )

      assert error.rc == 21
      assert error.message == "bad parameter or other API misuse"
      assert Exception.message(error) == "bad parameter or other API misuse"

      assert :done == Exqlite.step(conn, stmt)
    end
  end

  describe "serialize and deserialize" do
    test "serialize a database to binary and deserialize to new database" do
      path = tmp_path()
      {:ok, conn} = Exqlite.open(path)
      on_exit(fn -> :ok = Exqlite.close(conn) end)

      :ok =
        Exqlite.execute(conn, "create table test(id integer primary key, stuff text)")

      assert {:ok, binary} = Exqlite.serialize(conn)
      assert is_binary(binary)

      {:ok, conn} = Exqlite.open(":memory:")
      assert :ok = Exqlite.deserialize(conn, binary)

      assert :ok =
               Exqlite.execute(conn, "insert into test(id, stuff) values(1, 'hello')")

      assert {:ok, [[1, "hello"]]} =
               Exqlite.prepare_fetch_all(conn, "select * from test")
    end
  end

  describe "set_update_hook/2" do
    defmodule ChangeListener do
      use GenServer

      def start_link({parent, name}) do
        GenServer.start_link(__MODULE__, {parent, name})
      end

      def init({parent, name}), do: {:ok, {parent, name}}

      def handle_info({_action, _conn, _table, _row_id} = change, {parent, name}) do
        send(parent, {change, name})
        {:noreply, {parent, name}}
      end
    end

    setup do
      path = tmp_path()
      {:ok, conn} = Exqlite.open(path)
      on_exit(fn -> :ok = Exqlite.close(conn) end)

      :ok = Exqlite.execute(conn, "pragma journal_mode=wal")
      :ok = Exqlite.execute(conn, "create table test(num integer)")

      {:ok, conn: conn, path: path}
    end

    test "can listen to data change notifications", context do
      {:ok, listener_pid} = ChangeListener.start_link({self(), :listener})
      :ok = Exqlite.set_update_hook(context.conn, listener_pid)

      :ok = Exqlite.execute(context.conn, "insert into test(num) values (10)")
      :ok = Exqlite.execute(context.conn, "insert into test(num) values (11)")
      :ok = Exqlite.execute(context.conn, "update test set num = 1000")
      :ok = Exqlite.execute(context.conn, "delete from test where num = 1000")

      assert_receive {{:insert, "main", "test", 1}, _}
      assert_receive {{:insert, "main", "test", 2}, _}
      assert_receive {{:update, "main", "test", 1}, _}
      assert_receive {{:update, "main", "test", 2}, _}
      assert_receive {{:delete, "main", "test", 1}, _}
      assert_receive {{:delete, "main", "test", 2}, _}
      refute_receive _anything_else
    end

    test "only one pid can listen at a time", context do
      {:ok, listener1_pid} = ChangeListener.start_link({self(), :listener1})
      {:ok, listener2_pid} = ChangeListener.start_link({self(), :listener2})

      :ok = Exqlite.set_update_hook(context.conn, listener1_pid)
      :ok = Exqlite.execute(context.conn, "insert into test(num) values (10)")
      assert_receive {{:insert, "main", "test", 1}, :listener1}

      :ok = Exqlite.set_update_hook(context.conn, listener2_pid)
      :ok = Exqlite.execute(context.conn, "insert into test(num) values (10)")
      assert_receive {{:insert, "main", "test", 2}, :listener2}
      refute_receive {{:insert, "main", "test", 2}, :listener1}

      refute_receive _anything_else
    end

    test "notifications don't cross connections", context do
      {:ok, listener_pid} = ChangeListener.start_link({self(), :listener})
      {:ok, new_conn} = Exqlite.open(context.path)
      :ok = Exqlite.set_update_hook(new_conn, listener_pid)
      :ok = Exqlite.execute(context.conn, "insert into test(num) values (10)")
      refute_receive _anything
    end
  end

  describe "set_log_hook/1" do
    setup do
      {:ok, conn} = Exqlite.open(":memory:")
      on_exit(fn -> Exqlite.close(conn) end)
      {:ok, conn: conn}
    end

    test "can receive errors", %{conn: conn} do
      assert :ok = Exqlite.set_log_hook(self())

      assert {:error, %Exqlite.SQLiteError{rc: 1, message: "SQL logic error"}} =
               Exqlite.prepare(conn, "some invalid sql")

      assert_receive {:log, rc, msg}
      assert rc == 1
      assert msg == "near \"some\": syntax error in \"some invalid sql\""
      refute_receive _anything_else
    end

    test "only one pid can listen at a time", %{conn: conn} do
      assert :ok = Exqlite.set_log_hook(self())

      task =
        Task.async(fn ->
          :ok = Exqlite.set_log_hook(self())

          assert {:error, %Exqlite.SQLiteError{} = error} =
                   Exqlite.prepare(conn, "some invalid sql")

          assert error.rc == 1
          assert error.message == "SQL logic error"

          assert_receive {:log, rc, msg}
          assert rc == 1
          assert msg == "near \"some\": syntax error in \"some invalid sql\""
          refute_receive _anything_else
        end)

      Task.await(task)
      refute_receive _anything_else
    end

    test "receives notifications from all connections", %{conn: conn1} do
      assert :ok = Exqlite.set_log_hook(self())
      assert {:ok, conn2} = Exqlite.open(":memory:")
      on_exit(fn -> Exqlite.close(conn2) end)

      assert {:error, _reason} = Exqlite.prepare(conn1, "some invalid sql 1")
      assert_receive {:log, rc, msg}
      assert rc == 1
      assert msg == "near \"some\": syntax error in \"some invalid sql 1\""
      refute_receive _anything_else

      assert {:error, _reason} = Exqlite.prepare(conn2, "some invalid sql 2")
      assert_receive {:log, rc, msg}
      assert rc == 1
      assert msg == "near \"some\": syntax error in \"some invalid sql 2\""
      refute_receive _anything_else
    end
  end
end
