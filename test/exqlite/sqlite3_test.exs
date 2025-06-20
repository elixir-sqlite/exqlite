defmodule Exqlite.Sqlite3Test do
  use ExUnit.Case

  alias Exqlite.Sqlite3
  doctest Exqlite.Sqlite3

  describe ".open/1" do
    test "opens a database in memory" do
      {:ok, conn} = Sqlite3.open(":memory:")

      assert conn
    end

    test "opens a database on disk" do
      {:ok, path} = Temp.path()
      {:ok, conn} = Sqlite3.open(path)

      assert conn

      File.rm(path)
    end

    test "creates database path on disk when non-existent" do
      {:ok, path} = Temp.mkdir()
      {:ok, conn} = Sqlite3.open(path <> "/non_exist.db")

      assert conn

      File.rm(path)
    end

    test "opens a database in readonly mode" do
      # Create database with readwrite connection
      {:ok, path} = Temp.path()
      {:ok, rw_conn} = Sqlite3.open(path)

      create_table_query = "create table test (id integer primary key, stuff text)"
      :ok = Sqlite3.execute(rw_conn, create_table_query)

      insert_value_query = "insert into test (stuff) values ('This is a test')"
      :ok = Sqlite3.execute(rw_conn, insert_value_query)

      # Read from database with a readonly connection
      {:ok, ro_conn} = Sqlite3.open(path, mode: :readonly)

      select_query = "select id, stuff from test order by id asc"
      {:ok, statement} = Sqlite3.prepare(ro_conn, select_query)
      {:row, columns} = Sqlite3.step(ro_conn, statement)

      assert [1, "This is a test"] == columns

      # Readonly connection cannot insert
      assert {:error, "attempt to write a readonly database"} ==
               Sqlite3.execute(ro_conn, insert_value_query)
    end

    test "opens a database in a list of mode" do
      # Create database with readwrite connection
      {:ok, path} = Temp.path()
      {:ok, rw_conn} = Sqlite3.open(path)

      create_table_query = "create table test (id integer primary key, stuff text)"
      :ok = Sqlite3.execute(rw_conn, create_table_query)

      insert_value_query = "insert into test (stuff) values ('This is a test')"
      :ok = Sqlite3.execute(rw_conn, insert_value_query)

      # Read from database with a readonly connection
      {:ok, ro_conn} = Sqlite3.open(path, mode: [:readonly, :nomutex])

      select_query = "select id, stuff from test order by id asc"
      {:ok, statement} = Sqlite3.prepare(ro_conn, select_query)
      {:row, columns} = Sqlite3.step(ro_conn, statement)

      assert [1, "This is a test"] == columns
    end

    test "opens a database with invalid mode" do
      {:ok, path} = Temp.path()

      msg =
        "expected mode to be `:readwrite`, `:readonly` or list of modes, but received :notarealmode"

      assert_raise ArgumentError, msg, fn ->
        Sqlite3.open(path, mode: :notarealmode)
      end
    end

    test "opens a database with invalid single nomutex mode" do
      {:ok, path} = Temp.path()

      msg =
        "expected mode to be `:readwrite` or `:readonly`, can't use a single :nomutex mode"

      assert_raise ArgumentError, msg, fn ->
        Sqlite3.open(path, mode: :nomutex)
      end
    end

    test "opens a database with invalid list of mode" do
      {:ok, path} = Temp.path()

      msg =
        "expected mode to be `:readwrite`, `:readonly` or `:nomutex`, but received :notarealmode"

      assert_raise ArgumentError, msg, fn ->
        Sqlite3.open(path, mode: [:notarealmode])
      end
    end
  end

  describe ".close/2" do
    test "closes a database in memory" do
      {:ok, conn} = Sqlite3.open(":memory:")
      :ok = Sqlite3.close(conn)
    end

    test "closing a database multiple times works properly" do
      {:ok, conn} = Sqlite3.open(":memory:")
      :ok = Sqlite3.close(conn)
      :ok = Sqlite3.close(conn)
    end
  end

  describe ".execute/2" do
    test "creates a table" do
      {:ok, conn} = Sqlite3.open(":memory:")

      :ok =
        Sqlite3.execute(conn, "create table test (id integer primary key, stuff text)")

      :ok = Sqlite3.execute(conn, "insert into test (stuff) values ('This is a test')")
      {:ok, 1} = Sqlite3.last_insert_rowid(conn)
      {:ok, 1} = Sqlite3.changes(conn)
      :ok = Sqlite3.close(conn)
    end

    test "handles incorrect syntax" do
      {:ok, conn} = Sqlite3.open(":memory:")

      {:error, ~s|near "a": syntax error|} =
        Sqlite3.execute(
          conn,
          "create a dumb table test (id integer primary key, stuff text)"
        )

      {:ok, 0} = Sqlite3.changes(conn)
      :ok = Sqlite3.close(conn)
    end

    test "creates a virtual table with fts3" do
      {:ok, conn} = Sqlite3.open(":memory:")

      :ok =
        Sqlite3.execute(conn, "create virtual table things using fts3(content text)")

      :ok =
        Sqlite3.execute(conn, "insert into things(content) VALUES ('this is content')")
    end

    test "creates a virtual table with fts4" do
      {:ok, conn} = Sqlite3.open(":memory:")

      :ok =
        Sqlite3.execute(conn, "create virtual table things using fts4(content text)")

      :ok =
        Sqlite3.execute(conn, "insert into things(content) VALUES ('this is content')")
    end

    test "creates a virtual table with fts5" do
      {:ok, conn} = Sqlite3.open(":memory:")

      :ok = Sqlite3.execute(conn, "create virtual table things using fts5(content)")

      :ok =
        Sqlite3.execute(conn, "insert into things(content) VALUES ('this is content')")
    end

    test "handles unicode characters" do
      {:ok, conn} = Sqlite3.open(":memory:")

      :ok =
        Exqlite.Sqlite3.execute(
          conn,
          "create table test (id integer primary key, stuff text)"
        )

      :ok = Exqlite.Sqlite3.execute(conn, "insert into test (stuff) values ('😝')")
    end
  end

  describe ".prepare/3" do
    test "preparing a valid sql statement" do
      {:ok, conn} = Sqlite3.open(":memory:")

      :ok =
        Sqlite3.execute(conn, "create table test (id integer primary key, stuff text)")

      {:ok, statement} = Sqlite3.prepare(conn, "insert into test (stuff) values (?1)")

      assert statement
    end

    test "supports utf8 in error messages" do
      {:ok, conn} = Sqlite3.open(":memory:")
      assert {:error, "no such table: 🌍"} = Sqlite3.prepare(conn, "select * from 🌍")
    end
  end

  describe ".release/2" do
    test "double releasing a statement" do
      {:ok, conn} = Sqlite3.open(":memory:")

      :ok =
        Sqlite3.execute(conn, "create table test (id integer primary key, stuff text)")

      {:ok, statement} = Sqlite3.prepare(conn, "insert into test (stuff) values (?1)")
      :ok = Sqlite3.release(conn, statement)
      :ok = Sqlite3.release(conn, statement)
    end

    test "releasing a statement" do
      {:ok, conn} = Sqlite3.open(":memory:")

      :ok =
        Sqlite3.execute(conn, "create table test (id integer primary key, stuff text)")

      {:ok, statement} = Sqlite3.prepare(conn, "insert into test (stuff) values (?1)")
      :ok = Sqlite3.release(conn, statement)
    end

    test "releasing a nil statement" do
      {:ok, conn} = Sqlite3.open(":memory:")
      :ok = Sqlite3.release(conn, nil)
    end
  end

  describe ".bind" do
    test "binding values to a valid sql statement" do
      {:ok, conn} = Sqlite3.open(":memory:")

      :ok =
        Sqlite3.execute(conn, "create table test (id integer primary key, stuff text)")

      {:ok, statement} = Sqlite3.prepare(conn, "insert into test (stuff) values (?1)")
      :ok = Sqlite3.bind(statement, ["testing"])
    end

    test "trying to bind with incorrect amount of arguments" do
      {:ok, conn} = Sqlite3.open(":memory:")

      :ok =
        Sqlite3.execute(conn, "create table test (id integer primary key, stuff text)")

      {:ok, statement} = Sqlite3.prepare(conn, "insert into test (stuff) values (?1)")

      assert_raise ArgumentError, "expected 1 arguments, got 0", fn ->
        Sqlite3.bind(statement, [])
      end
    end

    test "binds datetime value as string" do
      {:ok, conn} = Sqlite3.open(":memory:")

      :ok =
        Sqlite3.execute(conn, "create table test (id integer primary key, stuff text)")

      {:ok, statement} = Sqlite3.prepare(conn, "insert into test (stuff) values (?1)")
      :ok = Sqlite3.bind(statement, [DateTime.utc_now()])
    end

    test "binds date value as string" do
      {:ok, conn} = Sqlite3.open(":memory:")

      :ok =
        Sqlite3.execute(conn, "create table test (id integer primary key, stuff text)")

      {:ok, statement} = Sqlite3.prepare(conn, "insert into test (stuff) values (?1)")
      :ok = Sqlite3.bind(statement, [Date.utc_today()])
    end

    test "raises an error when binding non UTC datetimes" do
      {:ok, conn} = Sqlite3.open(":memory:")

      :ok =
        Sqlite3.execute(conn, "create table test (id integer primary key, stuff text)")

      {:ok, statement} = Sqlite3.prepare(conn, "insert into test (stuff) values (?1)")

      msg = "#DateTime<2021-08-25 13:23:25+00:00 UTC Europe/Berlin> is not in UTC"

      assert_raise ArgumentError, msg, fn ->
        {:ok, dt} = DateTime.from_naive(~N[2021-08-25 13:23:25], "Etc/UTC")
        # Sneak in other timezone without a tz database
        other_tz = struct(dt, time_zone: "Europe/Berlin")

        Sqlite3.bind(statement, [other_tz])
      end
    end

    test "binds named parameters" do
      {:ok, conn} = Sqlite3.open(":memory:")

      {:ok, statement} =
        Sqlite3.prepare(conn, "select :42, @pi, :name, $👋, :blob, :null")

      :ok =
        Sqlite3.bind(statement, %{
          ":42" => 42,
          "@pi" => 3.14,
          :":name" => "Alice",
          "$👋" => "👋",
          ":blob" => {:blob, <<0, 1, 2>>},
          ~c":null" => nil
        })

      assert {:row, [42, 3.14, "Alice", "👋", <<0, 1, 2>>, nil]} =
               Sqlite3.step(conn, statement)
    end

    test "handles repeating named parameters" do
      {:ok, conn} = Sqlite3.open(":memory:")

      {:ok, statement} =
        Sqlite3.prepare(conn, "select :name, :name, :name")

      :ok =
        Sqlite3.bind(statement, %{
          ":name" => "Alice"
        })

      assert {:row, ["Alice", "Alice", "Alice"]} = Sqlite3.step(conn, statement)
    end

    test "raises an error when too few or too many named parameters" do
      {:ok, conn} = Sqlite3.open(":memory:")

      {:ok, statement} =
        Sqlite3.prepare(conn, "select :name, :age")

      assert_raise ArgumentError, ~r"expected 2 named arguments, got 1", fn ->
        Sqlite3.bind(statement, %{":name" => "Alice"})
      end

      assert_raise ArgumentError, ~r"expected 2 named arguments, got 3", fn ->
        Sqlite3.bind(statement, %{":name" => "Alice", ":age" => 30, ":extra" => "value"})
      end
    end
  end

  describe ".bind_text/3" do
    setup do
      {:ok, conn} = Sqlite3.open(":memory:", [:readonly])
      {:ok, stmt} = Sqlite3.prepare(conn, "select ?")
      {:ok, conn: conn, stmt: stmt}
    end

    test "binds text value", %{conn: conn, stmt: stmt} do
      assert :ok = Sqlite3.bind_text(stmt, 1, "hello")
      assert {:row, ["hello"]} = Sqlite3.step(conn, stmt)
    end

    test "binds emojis", %{conn: conn, stmt: stmt} do
      assert :ok = Sqlite3.bind_text(stmt, 1, "hello 👋 world 🌏")
      assert {:row, ["hello 👋 world 🌏"]} = Sqlite3.step(conn, stmt)
    end

    test "errors on invalid statement" do
      assert_raise ArgumentError, "argument error: nil", fn ->
        Sqlite3.bind_text(_not_stmt = nil, 1, "hello")
      end
    end

    test "errors on invalid index", %{stmt: stmt} do
      assert_raise Exqlite.Error, "column index out of range", fn ->
        Sqlite3.bind_text(stmt, _out_of_range = 2, "hello")
      end
    end

    test "errors on invalid text argument", %{stmt: stmt} do
      assert_raise ArgumentError, "argument error: 1", fn ->
        Sqlite3.bind_text(stmt, 1, _not_text = 1)
      end
    end
  end

  describe ".bind_blob/3" do
    setup do
      {:ok, conn} = Sqlite3.open(":memory:", [:readonly])
      {:ok, stmt} = Sqlite3.prepare(conn, "select ?")
      {:ok, conn: conn, stmt: stmt}
    end

    test "binds binary value", %{conn: conn, stmt: stmt} do
      assert :ok = Sqlite3.bind_blob(stmt, 1, <<0, 0, 0>>)
      assert {:row, [<<0, 0, 0>>]} = Sqlite3.step(conn, stmt)
    end

    test "errors on invalid statement" do
      assert_raise ArgumentError, "argument error: nil", fn ->
        Sqlite3.bind_blob(_not_stmt = nil, 1, "hello")
      end
    end

    test "errors on invalid index", %{stmt: stmt} do
      assert_raise Exqlite.Error, "column index out of range", fn ->
        Sqlite3.bind_blob(stmt, _out_of_range = 2, "hello")
      end
    end

    test "errors on invalid blob argument", %{stmt: stmt} do
      assert_raise ArgumentError, "argument error: 1", fn ->
        Sqlite3.bind_blob(stmt, 1, _not_binary = 1)
      end
    end
  end

  describe ".bind_integer/3" do
    setup do
      {:ok, conn} = Sqlite3.open(":memory:", [:readonly])
      {:ok, stmt} = Sqlite3.prepare(conn, "select ?")
      {:ok, conn: conn, stmt: stmt}
    end

    test "binds integer value", %{conn: conn, stmt: stmt} do
      assert :ok = Sqlite3.bind_integer(stmt, 1, 42)
      assert {:row, [42]} = Sqlite3.step(conn, stmt)
    end

    test "binds integers larger than INT32_MAX", %{conn: conn, stmt: stmt} do
      assert :ok = Sqlite3.bind_integer(stmt, 1, 0xFFFFFFFF + 1)
      assert {:row, [0x100000000]} = Sqlite3.step(conn, stmt)
    end

    test "errors on invalid statement" do
      assert_raise ArgumentError, "argument error: nil", fn ->
        Sqlite3.bind_integer(_not_stmt = nil, 1, 42)
      end
    end

    test "errors on invalid index", %{stmt: stmt} do
      assert_raise Exqlite.Error, "column index out of range", fn ->
        Sqlite3.bind_integer(stmt, _out_of_range = 2, 42)
      end
    end

    test "errors on invalid blob argument", %{stmt: stmt} do
      assert_raise ArgumentError, "argument error: \"42\"", fn ->
        Sqlite3.bind_integer(stmt, 1, _not_integer = "42")
      end
    end
  end

  describe ".bind_float/3" do
    setup do
      {:ok, conn} = Sqlite3.open(":memory:", [:readonly])
      {:ok, stmt} = Sqlite3.prepare(conn, "select ?")
      {:ok, conn: conn, stmt: stmt}
    end

    test "binds float value", %{conn: conn, stmt: stmt} do
      assert :ok = Sqlite3.bind_float(stmt, 1, 3.14)
      assert {:row, [3.14]} = Sqlite3.step(conn, stmt)
    end

    test "errors on invalid statement" do
      assert_raise ArgumentError, "argument error: nil", fn ->
        Sqlite3.bind_float(_not_stmt = nil, 1, 3.14)
      end
    end

    test "errors on invalid index", %{stmt: stmt} do
      assert_raise Exqlite.Error, "column index out of range", fn ->
        Sqlite3.bind_float(stmt, _out_of_range = 2, 3.14)
      end
    end

    test "errors on invalid blob argument", %{stmt: stmt} do
      assert_raise ArgumentError, "argument error: \"3.14\"", fn ->
        Sqlite3.bind_float(stmt, 1, _not_float = "3.14")
      end
    end
  end

  describe ".bind_null/2" do
    setup do
      {:ok, conn} = Sqlite3.open(":memory:", [:readonly])
      {:ok, stmt} = Sqlite3.prepare(conn, "select ?")
      {:ok, conn: conn, stmt: stmt}
    end

    test "binds null value", %{conn: conn, stmt: stmt} do
      assert :ok = Sqlite3.bind_null(stmt, 1)
      assert {:row, [nil]} = Sqlite3.step(conn, stmt)
    end

    test "errors on invalid statement" do
      assert_raise ArgumentError, "argument error: nil", fn ->
        Sqlite3.bind_null(_not_stmt = nil, 1)
      end
    end

    test "errors on invalid index", %{stmt: stmt} do
      assert_raise Exqlite.Error, "column index out of range", fn ->
        Sqlite3.bind_null(stmt, _out_of_range = 2)
      end
    end
  end

  describe ".columns/2" do
    test "returns the column definitions" do
      {:ok, conn} = Sqlite3.open(":memory:")

      :ok =
        Sqlite3.execute(conn, "create table test (id integer primary key, stuff text)")

      {:ok, statement} = Sqlite3.prepare(conn, "select id, stuff from test")

      {:ok, columns} = Sqlite3.columns(conn, statement)

      assert ["id", "stuff"] == columns
    end

    test "supports utf8 column names" do
      {:ok, conn} = Sqlite3.open(":memory:")
      :ok = Sqlite3.execute(conn, "create table test(👋 text, ✍️ text)")
      {:ok, statement} = Sqlite3.prepare(conn, "select * from test")
      assert {:ok, ["👋", "✍️"]} = Sqlite3.columns(conn, statement)
    end
  end

  describe ".step/2" do
    test "returns results" do
      {:ok, conn} = Sqlite3.open(":memory:")

      :ok =
        Sqlite3.execute(conn, "create table test (id integer primary key, stuff text)")

      :ok = Sqlite3.execute(conn, "insert into test (stuff) values ('This is a test')")
      {:ok, 1} = Sqlite3.last_insert_rowid(conn)
      :ok = Sqlite3.execute(conn, "insert into test (stuff) values ('Another test')")
      {:ok, 2} = Sqlite3.last_insert_rowid(conn)

      {:ok, statement} =
        Sqlite3.prepare(conn, "select id, stuff from test order by id asc")

      {:row, columns} = Sqlite3.step(conn, statement)
      assert [1, "This is a test"] == columns
      {:row, columns} = Sqlite3.step(conn, statement)
      assert [2, "Another test"] == columns
      assert :done = Sqlite3.step(conn, statement)

      {:row, columns} = Sqlite3.step(conn, statement)
      assert [1, "This is a test"] == columns
      {:row, columns} = Sqlite3.step(conn, statement)
      assert [2, "Another test"] == columns
      assert :done = Sqlite3.step(conn, statement)
    end

    test "returns no results" do
      {:ok, conn} = Sqlite3.open(":memory:")

      :ok =
        Sqlite3.execute(conn, "create table test (id integer primary key, stuff text)")

      {:ok, statement} = Sqlite3.prepare(conn, "select id, stuff from test")
      assert :done = Sqlite3.step(conn, statement)
    end

    test "works with insert" do
      {:ok, conn} = Sqlite3.open(":memory:")

      :ok =
        Sqlite3.execute(conn, "create table test (id integer primary key, stuff text)")

      {:ok, statement} = Sqlite3.prepare(conn, "insert into test (stuff) values (?1)")
      :ok = Sqlite3.bind(statement, ["this is a test"])
      assert :done == Sqlite3.step(conn, statement)
    end

    test "bind raises an exception" do
      {:ok, conn} = Sqlite3.open(":memory:")

      :ok =
        Sqlite3.execute(conn, "create table test (id integer primary key, stuff text)")

      {:ok, statement} = Sqlite3.prepare(conn, "insert into test (stuff) values (?1)")

      assert_raise ArgumentError,
                   "unsupported type: %ArgumentError{message: \"argument error\"}",
                   fn -> Sqlite3.bind(statement, [%ArgumentError{}]) end
    end
  end

  describe ".multi_step/3" do
    test "returns results" do
      {:ok, conn} = Sqlite3.open(":memory:")

      :ok =
        Sqlite3.execute(conn, "create table test (id integer primary key, stuff text)")

      :ok = Sqlite3.execute(conn, "insert into test (stuff) values ('one')")
      :ok = Sqlite3.execute(conn, "insert into test (stuff) values ('two')")
      :ok = Sqlite3.execute(conn, "insert into test (stuff) values ('three')")
      :ok = Sqlite3.execute(conn, "insert into test (stuff) values ('four')")
      :ok = Sqlite3.execute(conn, "insert into test (stuff) values ('five')")
      :ok = Sqlite3.execute(conn, "insert into test (stuff) values ('six')")

      {:ok, statement} =
        Sqlite3.prepare(conn, "select id, stuff from test order by id asc")

      {:rows, rows} = Sqlite3.multi_step(conn, statement, 4)
      assert rows == [[1, "one"], [2, "two"], [3, "three"], [4, "four"]]

      {:done, rows} = Sqlite3.multi_step(conn, statement, 4)
      assert rows == [[5, "five"], [6, "six"]]
    end
  end

  describe ".multi_step/2" do
    test "returns results" do
      {:ok, conn} = Sqlite3.open(":memory:")

      :ok =
        Sqlite3.execute(conn, "create table test (id integer primary key, stuff text)")

      :ok = Sqlite3.execute(conn, "insert into test (stuff) values ('one')")
      :ok = Sqlite3.execute(conn, "insert into test (stuff) values ('two')")
      :ok = Sqlite3.execute(conn, "insert into test (stuff) values ('three')")
      :ok = Sqlite3.execute(conn, "insert into test (stuff) values ('four')")
      :ok = Sqlite3.execute(conn, "insert into test (stuff) values ('five')")
      :ok = Sqlite3.execute(conn, "insert into test (stuff) values ('six')")

      {:ok, statement} =
        Sqlite3.prepare(conn, "select id, stuff from test order by id asc")

      {:done, rows} = Sqlite3.multi_step(conn, statement)

      assert rows == [
               [1, "one"],
               [2, "two"],
               [3, "three"],
               [4, "four"],
               [5, "five"],
               [6, "six"]
             ]
    end
  end

  describe "working with prepared statements after close" do
    test "returns proper error" do
      {:ok, conn} = Sqlite3.open(":memory:")

      :ok =
        Sqlite3.execute(conn, "create table test (id integer primary key, stuff text)")

      {:ok, statement} = Sqlite3.prepare(conn, "insert into test (stuff) values (?1)")
      :ok = Sqlite3.close(conn)
      :ok = Sqlite3.bind(statement, ["this is a test"])

      {:error, message} =
        Sqlite3.execute(conn, "create table test (id integer primary key, stuff text)")

      assert message == "Sqlite3 was invoked incorrectly."

      assert :done == Sqlite3.step(conn, statement)
    end
  end

  describe "serialize and deserialize" do
    test "serialize a database to binary and deserialize to new database" do
      {:ok, path} = Temp.path()
      {:ok, conn} = Sqlite3.open(path)

      :ok =
        Sqlite3.execute(conn, "create table test(id integer primary key, stuff text)")

      assert {:ok, binary} = Sqlite3.serialize(conn, "main")
      assert is_binary(binary)
      Sqlite3.close(conn)
      File.rm(path)

      {:ok, conn} = Sqlite3.open(":memory:")
      assert :ok = Sqlite3.deserialize(conn, "main", binary)

      assert :ok =
               Sqlite3.execute(conn, "insert into test(id, stuff) values (1, 'hello')")

      assert {:ok, statement} = Sqlite3.prepare(conn, "select id, stuff from test")
      assert {:row, [1, "hello"]} = Sqlite3.step(conn, statement)
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

    setup do
      {:ok, path} = Temp.path()
      {:ok, conn} = Sqlite3.open(path)
      :ok = Sqlite3.execute(conn, "create table test(num integer)")

      on_exit(fn ->
        Sqlite3.close(conn)
        File.rm(path)
      end)

      [conn: conn, path: path]
    end

    test "can listen to data change notifications", context do
      {:ok, listener_pid} = ChangeListener.start_link({self(), :listener})
      Sqlite3.set_update_hook(context.conn, listener_pid)

      :ok = Sqlite3.execute(context.conn, "insert into test(num) values (10)")
      :ok = Sqlite3.execute(context.conn, "insert into test(num) values (11)")
      :ok = Sqlite3.execute(context.conn, "update test set num = 1000")
      :ok = Sqlite3.execute(context.conn, "delete from test where num = 1000")

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

      Sqlite3.set_update_hook(context.conn, listener1_pid)
      :ok = Sqlite3.execute(context.conn, "insert into test(num) values (10)")
      assert_receive {{:insert, "main", "test", 1}, :listener1}, 1000

      Sqlite3.set_update_hook(context.conn, listener2_pid)
      :ok = Sqlite3.execute(context.conn, "insert into test(num) values (10)")
      assert_receive {{:insert, "main", "test", 2}, :listener2}, 1000
      refute_receive {{:insert, "main", "test", 2}, :listener1}, 1000
    end

    test "notifications don't cross connections", context do
      {:ok, listener_pid} = ChangeListener.start_link({self(), :listener})
      {:ok, new_conn} = Sqlite3.open(context.path)
      Sqlite3.set_update_hook(new_conn, listener_pid)
      :ok = Sqlite3.execute(context.conn, "insert into test(num) values (10)")
      refute_receive {{:insert, "main", "test", 1}, _}, 1000
    end
  end

  describe "set_log_hook/1" do
    setup do
      {:ok, conn} = Sqlite3.open(":memory:")
      on_exit(fn -> Sqlite3.close(conn) end)
      {:ok, conn: conn}
    end

    test "can receive errors", %{conn: conn} do
      assert :ok = Sqlite3.set_log_hook(self())

      assert {:error, reason} = Sqlite3.prepare(conn, "some invalid sql")
      assert reason == "near \"some\": syntax error"

      assert_receive {:log, rc, msg}
      assert rc == 1
      assert msg == "near \"some\": syntax error in \"some invalid sql\""
      refute_receive _anything_else
    end

    test "only one pid can listen at a time", %{conn: conn} do
      assert :ok = Sqlite3.set_log_hook(self())

      task =
        Task.async(fn ->
          :ok = Sqlite3.set_log_hook(self())
          assert {:error, reason} = Sqlite3.prepare(conn, "some invalid sql")
          assert reason == "near \"some\": syntax error"
          assert_receive {:log, rc, msg}
          assert rc == 1
          assert msg == "near \"some\": syntax error in \"some invalid sql\""
          refute_receive _anything_else
        end)

      Task.await(task)
      refute_receive _anything_else
    end

    test "receives notifications from all connections", %{conn: conn1} do
      assert :ok = Sqlite3.set_log_hook(self())
      assert {:ok, conn2} = Sqlite3.open(":memory:")
      on_exit(fn -> Sqlite3.close(conn2) end)

      assert {:error, _reason} = Sqlite3.prepare(conn1, "some invalid sql 1")
      assert_receive {:log, rc, msg}
      assert rc == 1
      assert msg == "near \"some\": syntax error in \"some invalid sql 1\""
      refute_receive _anything_else

      assert {:error, _reason} = Sqlite3.prepare(conn2, "some invalid sql 2")
      assert_receive {:log, rc, msg}
      assert rc == 1
      assert msg == "near \"some\": syntax error in \"some invalid sql 2\""
      refute_receive _anything_else
    end
  end

  describe ".interrupt/1" do
    test "double interrupting a connection" do
      {:ok, conn} = Sqlite3.open(":memory:")

      :ok = Sqlite3.interrupt(conn)
      :ok = Sqlite3.interrupt(conn)
    end

    test "interrupting a nil connection" do
      :ok = Sqlite3.interrupt(nil)
    end

    test "interrupting a long running query and able to close a connection" do
      {:ok, conn} = Sqlite3.open(":memory:")

      spawn(fn ->
        :ok =
          Sqlite3.execute(
            conn,
            "WITH RECURSIVE r(i) AS ( VALUES(0) UNION ALL SELECT i FROM r LIMIT 1000000000 ) SELECT i FROM r WHERE i = 1;"
          )
      end)

      Process.sleep(100)
      :ok = Sqlite3.interrupt(conn)
      Process.sleep(100)
      :ok = Sqlite3.close(conn)
    end
  end
end
