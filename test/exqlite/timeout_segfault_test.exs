defmodule Exqlite.TimeoutSegfaultTest do
  use ExUnit.Case

  @moduletag :slow_test

  setup do
    {:ok, path} = Temp.path()
    on_exit(fn -> File.rm(path) end)

    %{path: path}
  end

  test "segfault", %{path: path} do
    {:ok, conn} =
      DBConnection.start_link(Exqlite.Connection,
        busy_timeout: 50_000,
        pool_size: 50,
        timeout: 1,
        database: path,
        journal_mode: :wal
      )

    query = %Exqlite.Query{statement: "create table foo(id integer, val integer)"}
    {:ok, _, _} = DBConnection.execute(conn, query, [])

    values = for i <- 1..1000, do: "(#{i}, #{i})"
    statement = "insert into foo(id, val) values #{Enum.join(values, ",")}"
    insert_query = %Exqlite.Query{statement: statement}

    1..5000
    |> Task.async_stream(fn _ ->
      try do
        DBConnection.execute(conn, insert_query, [], timeout: 1)
      catch
        kind, reason ->
          IO.puts("Error: #{inspect(kind)} reason: #{inspect(reason)}")
      end
    end)
    |> Stream.run()
  end
end
