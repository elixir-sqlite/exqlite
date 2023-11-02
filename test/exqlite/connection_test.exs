defmodule Exqlite.ConnectionTest do
  use ExUnit.Case

  alias Exqlite.Connection
  alias Exqlite.Query
  alias Exqlite.Sqlite3

  describe ".connect/1" do
    test "returns error when path is missing from options" do
      {:error, error} = Connection.connect([])

      assert error.message ==
               ~s{You must provide a :database to the database. Example: connect(database: "./") or connect(database: :memory)}
    end

    test "connects to an in memory database" do
      {:ok, state} = Connection.connect(database: ":memory:")

      assert state.path == ":memory:"
      assert state.db
    end

    test "connects to in memory when the memory atom is passed" do
      {:ok, state} = Connection.connect(database: :memory)

      assert state.path == ":memory:"
      assert state.db
    end

    test "connects to a file" do
      path = Temp.path!()
      {:ok, state} = Connection.connect(database: path)

      assert state.path == path
      assert state.db

      File.rm(path)
    end

    test "connects to a file from URL" do
      path = Temp.path!()

      {:ok, state} = Connection.connect(database: "file:#{path}?mode=rwc")

      assert state.directory == Path.dirname(path)
      assert state.db
    end

    test "fails to write a file from URL with mode=ro" do
      path = Temp.path!()

      {:ok, db} = Sqlite3.open(path)

      :ok =
        Sqlite3.execute(db, "create table test (id ingeger primary key, stuff text)")

      :ok =
        Sqlite3.execute(db, "insert into test (id, stuff) values (999, 'Some stuff')")

      :ok = Sqlite3.close(db)

      {:ok, conn} = Connection.connect(database: "file:#{path}?mode=ro")

      assert conn.directory == Path.dirname(path)
      assert conn.db

      assert match?(
               {:ok, _, %{rows: [[1]]}, _},
               %Query{statement: "select count(*) from test"}
               |> Connection.handle_execute([], [], conn)
             )

      {:error, %{message: message}, _} =
        %Query{
          statement: "insert into test (id, stuff) values (888, 'some more stuff')"
        }
        |> Connection.handle_execute([], [], conn)

      # In most of the test matrix the message is "attempt to write a readonly database",
      # but in Elixir 1.13, OTP 23, OS windows-2019 it is "not an error".
      assert message in ["attempt to write a readonly database", "not an error"]

      File.rm(path)
    end

    test "setting custom_pragmas" do
      path = Temp.path!()

      {:ok, state} =
        Connection.connect(
          database: path,
          custom_pragmas: [
            checkpoint_fullfsync: 0
          ]
        )

      assert state.db

      assert {:ok, 0} = get_pragma(state.db, :checkpoint_fullfsync)

      File.rm(path)
    end

    test "setting journal_size_limit" do
      path = Temp.path!()
      size_limit = 20 * 1024 * 1024
      {:ok, state} = Connection.connect(database: path, journal_size_limit: size_limit)

      assert state.db

      assert {:ok, ^size_limit} = get_pragma(state.db, :journal_size_limit)

      File.rm(path)
    end

    test "setting soft_heap_limit" do
      path = Temp.path!()
      size_limit = 20 * 1024 * 1024
      {:ok, state} = Connection.connect(database: path, soft_heap_limit: size_limit)

      assert state.db

      assert {:ok, ^size_limit} = get_pragma(state.db, :soft_heap_limit)

      File.rm(path)
    end

    test "setting hard_heap_limit" do
      path = Temp.path!()
      size_limit = 20 * 1024 * 1024
      {:ok, state} = Connection.connect(database: path, hard_heap_limit: size_limit)

      assert state.db

      assert {:ok, ^size_limit} = get_pragma(state.db, :hard_heap_limit)

      File.rm(path)
    end

    test "setting connection mode" do
      path = Temp.path!()

      # Create readwrite connection
      {:ok, rw_state} = Connection.connect(database: path)
      create_table_query = "create table test (id integer primary key, stuff text)"
      :ok = Sqlite3.execute(rw_state.db, create_table_query)

      insert_value_query = "insert into test (stuff) values ('This is a test')"
      :ok = Sqlite3.execute(rw_state.db, insert_value_query)

      # Read from database with a readonly connection
      {:ok, ro_state} = Connection.connect(database: path, mode: :readonly)

      select_query = "select id, stuff from test order by id asc"
      {:ok, statement} = Sqlite3.prepare(ro_state.db, select_query)
      {:row, columns} = Sqlite3.step(ro_state.db, statement)

      assert [1, "This is a test"] == columns

      # Readonly connection cannot insert
      assert {:error, "attempt to write a readonly database"} ==
               Sqlite3.execute(ro_state.db, insert_value_query)
    end
  end

  defp get_pragma(db, pragma_name) do
    {:ok, statement} = Sqlite3.prepare(db, "PRAGMA #{pragma_name}")

    case Sqlite3.fetch_all(db, statement) do
      {:ok, [[value]]} -> {:ok, value}
      _ -> :error
    end
  end

  describe ".disconnect/2" do
    test "disconnects a database that was never connected" do
      conn = %Connection{db: nil, path: nil}

      assert :ok == Connection.disconnect(nil, conn)
    end

    test "disconnects a connected database" do
      {:ok, conn} = Connection.connect(database: :memory)

      assert :ok == Connection.disconnect(nil, conn)
    end

    test "executes before_disconnect before disconnecting" do
      {:ok, pid} = Agent.start_link(fn -> 0 end)

      {:ok, conn} =
        Connection.connect(
          database: :memory,
          before_disconnect: fn err, db ->
            Agent.update(pid, fn count -> count + 1 end)
            assert err == true
            assert db
          end
        )

      assert :ok == Connection.disconnect(true, conn)
      assert Agent.get(pid, &Function.identity/1) == 1
    end
  end

  describe ".handle_execute/4" do
    test "returns records" do
      path = Temp.path!()

      {:ok, db} = Sqlite3.open(path)

      :ok =
        Sqlite3.execute(db, "create table users (id integer primary key, name text)")

      :ok = Sqlite3.execute(db, "insert into users (id, name) values (1, 'Jim')")
      :ok = Sqlite3.execute(db, "insert into users (id, name) values (2, 'Bob')")
      :ok = Sqlite3.execute(db, "insert into users (id, name) values (3, 'Dave')")
      :ok = Sqlite3.execute(db, "insert into users (id, name) values (4, 'Steve')")
      Sqlite3.close(db)

      {:ok, conn} = Connection.connect(database: path)

      {:ok, _query, result, _conn} =
        %Query{statement: "select * from users where id < ?"}
        |> Connection.handle_execute([4], [], conn)

      assert result.command == :execute
      assert result.columns == ["id", "name"]
      assert result.rows == [[1, "Jim"], [2, "Bob"], [3, "Dave"]]

      File.rm(path)
    end

    test "returns correctly for empty result" do
      path = Temp.path!()

      {:ok, db} = Sqlite3.open(path)

      :ok =
        Sqlite3.execute(db, "create table users (id integer primary key, name text)")

      Sqlite3.close(db)

      {:ok, conn} = Connection.connect(database: path)

      {:ok, _query, result, _conn} =
        %Query{
          statement: "UPDATE users set name = 'wow' where id = 1",
          command: :update
        }
        |> Connection.handle_execute([], [], conn)

      assert result.rows == nil

      {:ok, _query, result, _conn} =
        %Query{
          statement: "UPDATE users set name = 'wow' where id = 5 returning *",
          command: :update
        }
        |> Connection.handle_execute([], [], conn)

      assert result.rows == []

      File.rm(path)
    end

    test "returns timely and in order for big data sets" do
      path = Temp.path!()

      {:ok, db} = Sqlite3.open(path)

      :ok =
        Sqlite3.execute(db, "create table users (id integer primary key, name text)")

      users =
        Enum.map(1..10_000, fn i ->
          [i, "User-#{i}"]
        end)

      users
      |> Enum.chunk_every(20)
      |> Enum.each(fn chunk ->
        values = Enum.map_join(chunk, ", ", fn [id, name] -> "(#{id}, '#{name}')" end)
        Sqlite3.execute(db, "insert into users (id, name) values #{values}")
      end)

      :ok = Exqlite.Sqlite3.close(db)

      {:ok, conn} = Connection.connect(database: path)

      {:ok, _query, result, _conn} =
        Connection.handle_execute(
          %Exqlite.Query{
            statement: "SELECT * FROM users"
          },
          [],
          [timeout: 1],
          conn
        )

      assert result.command == :execute
      assert length(result.rows) == 10_000
      assert users == result.rows

      File.rm(path)
    end
  end

  describe ".handle_prepare/3" do
    test "returns a prepared query" do
      {:ok, conn} = Connection.connect(database: :memory)

      {:ok, _query, _result, conn} =
        %Query{statement: "create table users (id integer primary key, name text)"}
        |> Connection.handle_execute([], [], conn)

      {:ok, query, conn} =
        %Query{statement: "select * from users where id < ?"}
        |> Connection.handle_prepare([], conn)

      assert conn
      assert query
      assert query.ref
      assert query.statement
    end

    test "users table does not exist" do
      {:ok, conn} = Connection.connect(database: :memory)

      {:error, error, _state} =
        %Query{statement: "select * from users where id < ?"}
        |> Connection.handle_prepare([], conn)

      assert error.message == "no such table: users"
    end
  end

  describe ".checkout/1" do
    test "checking out an idle connection" do
      {:ok, conn} = Connection.connect(database: :memory)

      {:ok, conn} = Connection.checkout(conn)
      assert conn.status == :busy
    end

    test "checking out a busy connection" do
      {:ok, conn} = Connection.connect(database: :memory)
      conn = %{conn | status: :busy}

      {:disconnect, error, _conn} = Connection.checkout(conn)

      assert error.message == "Database is busy"
    end
  end

  describe ".ping/1" do
    test "returns the state passed unchanged" do
      {:ok, conn} = Connection.connect(database: :memory)

      assert {:ok, conn} == Connection.ping(conn)
    end
  end

  describe ".handle_close/3" do
    test "releases the underlying prepared statement" do
      {:ok, conn} = Connection.connect(database: :memory)

      {:ok, query, _result, conn} =
        %Query{statement: "create table users (id integer primary key, name text)"}
        |> Connection.handle_execute([], [], conn)

      assert {:ok, nil, conn} == Connection.handle_close(query, [], conn)

      {:ok, query, conn} =
        %Query{statement: "select * from users where id < ?"}
        |> Connection.handle_prepare([], conn)

      assert {:ok, nil, conn} == Connection.handle_close(query, [], conn)
    end
  end
end
