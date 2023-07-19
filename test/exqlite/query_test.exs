defmodule Exqlite.QueryTest do
  use ExUnit.Case, async: true

  setup :create_conn!

  test "table reader integration", %{conn: conn} do
    assert {:ok, _} =
             Exqlite.RWConnection.query(conn, "CREATE TABLE tab(x integer, y text);")

    assert {:ok, _} =
             Exqlite.RWConnection.query(
               conn,
               "INSERT INTO tab(x, y) VALUES (1, 'a'), (2, 'b'), (3, 'c');"
             )

    assert {:ok, res} = Exqlite.RWConnection.query(conn, "SELECT * FROM tab;")

    assert res |> Table.to_rows() |> Enum.to_list() == [
             %{"x" => 1, "y" => "a"},
             %{"x" => 2, "y" => "b"},
             %{"x" => 3, "y" => "c"}
           ]

    columns = Table.to_columns(res)
    assert Enum.to_list(columns["x"]) == [1, 2, 3]
    assert Enum.to_list(columns["y"]) == ["a", "b", "c"]
  end

  defp create_conn!(_context) do
    path = Temp.path!()
    on_exit(fn -> File.rm(path) end)
    {:ok, conn: start_supervised!({Exqlite.RWConnection, database: "#{path}.db"})}
  end
end
