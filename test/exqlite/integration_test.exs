defmodule Exqlite.IntegrationTest do
  use ExUnit.Case

  alias Exqlite.Connection
  alias Exqlite.Sqlite3
  alias Exqlite.Query

  test "simple prepare execute and close" do
    path = Temp.path!()
    {:ok, db} = Sqlite3.open(path)
    :ok = Sqlite3.execute(db, "create table test (id ingeger primary key, stuff text)")
    :ok = Sqlite3.close(db)

    {:ok, conn} = Connection.connect(database: path)

    {:ok, query, _} =
      %Exqlite.Query{statement: "SELECT * FROM test WHERE id = :id"}
      |> Connection.handle_prepare([2], conn)

    {:ok, _query, result, conn} = Connection.handle_execute(query, [2], [], conn)
    assert result

    {:ok, _, conn} = Connection.handle_close(query, [], conn)
    assert conn

    File.rm(path)
  end

  test "transaction handling with concurrent connections" do
    path = Temp.path!()

    {:ok, conn1} =
      Connection.connect(
        database: path,
        journal_mode: :wal,
        cache_size: -64_000,
        temp_store: :memory
      )

    {:ok, conn2} =
      Connection.connect(
        database: path,
        journal_mode: :wal,
        cache_size: -64_000,
        temp_store: :memory
      )

    {:ok, _result, conn1} = Connection.handle_begin([], conn1)
    assert conn1.transaction_status == :transaction
    query = %Query{statement: "create table foo(id integer, val integer)"}
    {:ok, _query, _result, conn1} = Connection.handle_execute(query, [], [], conn1)
    {:ok, _result, conn1} = Connection.handle_rollback([], conn1)
    assert conn1.transaction_status == :idle

    {:ok, _result, conn2} = Connection.handle_begin([], conn2)
    assert conn2.transaction_status == :transaction
    query = %Query{statement: "create table foo(id integer, val integer)"}
    {:ok, _query, _result, conn2} = Connection.handle_execute(query, [], [], conn2)
    {:ok, _result, conn2} = Connection.handle_rollback([], conn2)
    assert conn2.transaction_status == :idle

    File.rm(path)
  end

  test "handles busy correctly" do
    path = Temp.path!()

    {:ok, conn1} =
      Connection.connect(
        database: path,
        journal_mode: :wal,
        cache_size: -64_000,
        temp_store: :memory,
        busy_timeout: 0
      )

    {:ok, conn2} =
      Connection.connect(
        database: path,
        journal_mode: :wal,
        cache_size: -64_000,
        temp_store: :memory,
        busy_timeout: 0
      )

    {:ok, _result, conn1} = Connection.handle_begin([mode: :immediate], conn1)
    assert conn1.transaction_status == :transaction
    {:disconnect, _err, conn2} = Connection.handle_begin([mode: :immediate], conn2)
    assert conn2.transaction_status == :idle
    {:ok, _result, conn1} = Connection.handle_commit([mode: :immediate], conn1)
    assert conn1.transaction_status == :idle
    {:ok, _result, conn2} = Connection.handle_begin([mode: :immediate], conn2)
    assert conn2.transaction_status == :transaction
    {:ok, _result, conn2} = Connection.handle_commit([mode: :immediate], conn2)
    assert conn2.transaction_status == :idle

    Connection.disconnect(nil, conn1)
    Connection.disconnect(nil, conn2)

    File.rm(path)
  end

  test "transaction with interleaved connections" do
    path = Temp.path!()

    {:ok, conn1} =
      Connection.connect(
        database: path,
        journal_mode: :wal,
        cache_size: -64_000,
        temp_store: :memory
      )

    {:ok, conn2} =
      Connection.connect(
        database: path,
        journal_mode: :wal,
        cache_size: -64_000,
        temp_store: :memory
      )

    {:ok, _result, conn1} = Connection.handle_begin([mode: :immediate], conn1)
    query = %Query{statement: "create table foo(id integer, val integer)"}
    {:ok, _query, _result, conn1} = Connection.handle_execute(query, [], [], conn1)

    # transaction overlap
    {:ok, _result, conn2} = Connection.handle_begin([], conn2)
    assert conn2.transaction_status == :transaction
    {:ok, _result, conn1} = Connection.handle_rollback([], conn1)
    assert conn1.transaction_status == :idle

    query = %Query{statement: "create table foo(id integer, val integer)"}
    {:ok, _query, _result, conn2} = Connection.handle_execute(query, [], [], conn2)
    {:ok, _result, conn2} = Connection.handle_rollback([], conn2)
    assert conn2.transaction_status == :idle

    Connection.disconnect(nil, conn1)
    Connection.disconnect(nil, conn2)

    File.rm(path)
  end

  test "transaction handling with single connection" do
    path = Temp.path!()

    {:ok, conn1} =
      Connection.connect(
        database: path,
        journal_mode: :wal,
        cache_size: -64_000,
        temp_store: :memory
      )

    {:ok, _result, conn1} = Connection.handle_begin([], conn1)
    assert conn1.transaction_status == :transaction

    query = %Query{statement: "create table foo(id integer, val integer)"}
    {:ok, _query, _result, conn1} = Connection.handle_execute(query, [], [], conn1)
    {:ok, _result, conn1} = Connection.handle_rollback([], conn1)
    assert conn1.transaction_status == :idle

    {:ok, _result, conn1} = Connection.handle_begin([], conn1)
    assert conn1.transaction_status == :transaction

    query = %Query{statement: "create table foo(id integer, val integer)"}
    {:ok, _query, _result, conn1} = Connection.handle_execute(query, [], [], conn1)
    {:ok, _result, conn1} = Connection.handle_rollback([], conn1)
    assert conn1.transaction_status == :idle

    File.rm(path)
  end

  test "transaction handling with immediate default_transaction_mode" do
    path = Temp.path!()

    {:ok, conn1} =
      Connection.connect(
        database: path,
        default_transaction_mode: :immediate,
        journal_mode: :wal,
        cache_size: -64_000,
        temp_store: :memory
      )

    {:ok, _result, conn1} = Connection.handle_begin([], conn1)
    assert conn1.transaction_status == :transaction
    assert conn1.default_transaction_mode == :immediate
    query = %Query{statement: "create table foo(id integer, val integer)"}
    {:ok, _query, _result, conn1} = Connection.handle_execute(query, [], [], conn1)
    {:ok, _result, conn1} = Connection.handle_rollback([], conn1)
    assert conn1.transaction_status == :idle

    File.rm(path)
  end

  test "transaction handling with default default_transaction_mode" do
    path = Temp.path!()

    {:ok, conn1} =
      Connection.connect(
        database: path,
        journal_mode: :wal,
        cache_size: -64_000,
        temp_store: :memory
      )

    {:ok, _result, conn1} = Connection.handle_begin([], conn1)
    assert conn1.transaction_status == :transaction
    assert conn1.default_transaction_mode == :deferred
    query = %Query{statement: "create table foo(id integer, val integer)"}
    {:ok, _query, _result, conn1} = Connection.handle_execute(query, [], [], conn1)
    {:ok, _result, conn1} = Connection.handle_rollback([], conn1)
    assert conn1.transaction_status == :idle

    File.rm(path)
  end

  test "exceeding timeout" do
    path = Temp.path!()

    {:ok, conn} =
      DBConnection.start_link(Connection,
        idle_interval: 5_000,
        database: path,
        journal_mode: :wal,
        cache_size: -64_000,
        temp_store: :memory
      )

    query = %Query{statement: "create table foo(id integer, val integer)"}
    {:ok, _, _} = DBConnection.execute(conn, query, [])

    values = for i <- 1..10_001, do: "(#{i}, #{i})"

    query = %Query{
      statement: "insert into foo(id, val) values #{Enum.join(values, ",")}"
    }

    {:ok, _, _} = DBConnection.execute(conn, query, [])

    query = %Query{statement: "select * from foo"}

    # With the cancellable busy handler (issue #192), disconnect now properly
    # interrupts running queries via the progress handler. So a query that
    # exceeds the checkout timeout may be interrupted rather than completing.
    case DBConnection.execute(conn, query, [], timeout: 1) do
      {:ok, _, _} -> :ok
      {:error, %Exqlite.Error{message: "interrupted"}} -> :ok
      {:error, %Exqlite.Error{message: msg}} ->
        flunk("Unexpected error while executing query: #{msg}")
    end

    File.rm(path)
  end

  test "can load a serialized database at startup" do
    {:ok, path} = Temp.path()
    {:ok, conn} = Sqlite3.open(path)

    :ok =
      Sqlite3.execute(conn, "create table test(id integer primary key, stuff text)")

    assert :ok =
             Sqlite3.execute(conn, "insert into test(id, stuff) values (1, 'hello')")

    assert {:ok, binary} = Sqlite3.serialize(conn, "main")
    assert is_binary(binary)
    Sqlite3.close(conn)
    File.rm(path)

    {:ok, conn} =
      DBConnection.start_link(Connection,
        idle_interval: 5_000,
        database: :memory,
        journal_mode: :wal,
        cache_size: -64_000,
        temp_store: :memory,
        serialized: binary
      )

    query = %Query{statement: "select id, stuff from test"}
    {:ok, _, result} = DBConnection.execute(conn, query, [])
    assert result.columns == ["id", "stuff"]
    assert result.rows == [[1, "hello"]]
  end
end
