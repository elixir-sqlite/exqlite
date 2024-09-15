# defmodule Exqlite.ConnectionTest do
#   use ExUnit.Case, async: true

#   describe ".disconnect/2" do
#     test "disconnects a database that was never connected" do
#       conn = %Connection{db: nil, path: nil}

#       assert :ok == Connection.disconnect(nil, conn)
#     end

#     test "disconnects a connected database" do
#       {:ok, conn} = Connection.connect(database: :memory)

#       assert :ok == Connection.disconnect(nil, conn)
#     end

#     test "executes before_disconnect before disconnecting" do
#       {:ok, pid} = Agent.start_link(fn -> 0 end)

#       {:ok, conn} =
#         Connection.connect(
#           database: :memory,
#           before_disconnect: fn err, db ->
#             Agent.update(pid, fn count -> count + 1 end)
#             assert err == true
#             assert db
#           end
#         )

#       assert :ok == Connection.disconnect(true, conn)
#       assert Agent.get(pid, &Function.identity/1) == 1
#     end
#   end

#   describe ".handle_execute/4" do
#     test "returns records" do
#       path = Temp.path!()

#       {:ok, db} = Sqlite3.open(path)

#       :ok =
#         Sqlite3.execute(db, "create table users (id integer primary key, name text)")

#       :ok = Sqlite3.execute(db, "insert into users (id, name) values (1, 'Jim')")
#       :ok = Sqlite3.execute(db, "insert into users (id, name) values (2, 'Bob')")
#       :ok = Sqlite3.execute(db, "insert into users (id, name) values (3, 'Dave')")
#       :ok = Sqlite3.execute(db, "insert into users (id, name) values (4, 'Steve')")
#       Sqlite3.close(db)

#       {:ok, conn} = Connection.connect(database: path)

#       {:ok, _query, result, _conn} =
#         %Query{statement: "select * from users where id < ?"}
#         |> Connection.handle_execute([4], [], conn)

#       assert result.command == :execute
#       assert result.columns == ["id", "name"]
#       assert result.rows == [[1, "Jim"], [2, "Bob"], [3, "Dave"]]

#       File.rm(path)
#     end

#     test "returns correctly for empty result" do
#       path = Temp.path!()

#       {:ok, db} = Sqlite3.open(path)

#       :ok =
#         Sqlite3.execute(db, "create table users (id integer primary key, name text)")

#       Sqlite3.close(db)

#       {:ok, conn} = Connection.connect(database: path)

#       {:ok, _query, result, _conn} =
#         %Query{
#           statement: "UPDATE users set name = 'wow' where id = 1",
#           command: :update
#         }
#         |> Connection.handle_execute([], [], conn)

#       assert result.rows == nil

#       {:ok, _query, result, _conn} =
#         %Query{
#           statement: "UPDATE users set name = 'wow' where id = 5 returning *",
#           command: :update
#         }
#         |> Connection.handle_execute([], [], conn)

#       assert result.rows == []

#       File.rm(path)
#     end

#     test "returns timely and in order for big data sets" do
#       path = Temp.path!()

#       {:ok, db} = Sqlite3.open(path)

#       :ok =
#         Sqlite3.execute(db, "create table users (id integer primary key, name text)")

#       users =
#         Enum.map(1..10_000, fn i ->
#           [i, "User-#{i}"]
#         end)

#       users
#       |> Enum.chunk_every(20)
#       |> Enum.each(fn chunk ->
#         values = Enum.map_join(chunk, ", ", fn [id, name] -> "(#{id}, '#{name}')" end)
#         Sqlite3.execute(db, "insert into users (id, name) values #{values}")
#       end)

#       :ok = Exqlite.Sqlite3.close(db)

#       {:ok, conn} = Connection.connect(database: path)

#       {:ok, _query, result, _conn} =
#         Connection.handle_execute(
#           %Exqlite.Query{
#             statement: "SELECT * FROM users"
#           },
#           [],
#           [timeout: 1],
#           conn
#         )

#       assert result.command == :execute
#       assert length(result.rows) == 10_000
#       assert users == result.rows

#       File.rm(path)
#     end
#   end

#   describe ".handle_prepare/3" do
#     test "returns a prepared query" do
#       {:ok, conn} = Connection.connect(database: :memory)

#       {:ok, _query, _result, conn} =
#         %Query{statement: "create table users (id integer primary key, name text)"}
#         |> Connection.handle_execute([], [], conn)

#       {:ok, query, conn} =
#         %Query{statement: "select * from users where id < ?"}
#         |> Connection.handle_prepare([], conn)

#       assert conn
#       assert query
#       assert query.ref
#       assert query.statement
#     end

#     test "users table does not exist" do
#       {:ok, conn} = Connection.connect(database: :memory)

#       {:error, error, _state} =
#         %Query{statement: "select * from users where id < ?"}
#         |> Connection.handle_prepare([], conn)

#       assert error.message == "no such table: users"
#     end
#   end

#   describe ".checkout/1" do
#     test "checking out an idle connection" do
#       {:ok, conn} = Connection.connect(database: :memory)

#       {:ok, conn} = Connection.checkout(conn)
#       assert conn.status == :busy
#     end

#     test "checking out a busy connection" do
#       {:ok, conn} = Connection.connect(database: :memory)
#       conn = %{conn | status: :busy}

#       {:disconnect, error, _conn} = Connection.checkout(conn)

#       assert error.message == "Database is busy"
#     end
#   end

#   describe ".handle_close/3" do
#     test "releases the underlying prepared statement" do
#       {:ok, conn} = Connection.connect(database: :memory)

#       {:ok, query, _result, conn} =
#         %Query{statement: "create table users (id integer primary key, name text)"}
#         |> Connection.handle_execute([], [], conn)

#       assert {:ok, nil, conn} == Connection.handle_close(query, [], conn)

#       {:ok, query, conn} =
#         %Query{statement: "select * from users where id < ?"}
#         |> Connection.handle_prepare([], conn)

#       assert {:ok, nil, conn} == Connection.handle_close(query, [], conn)
#     end
#   end
# end
