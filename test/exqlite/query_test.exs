defmodule Exqlite.QueryTest do
  use ExUnit.Case, async: true

  setup :create_conn!

  test "table reader integration", %{conn: conn} do
    assert {:ok, _} = Exqlite.query(conn, "CREATE TABLE tab(x integer, y text);", [])

    assert {:ok, _} =
             Exqlite.query(
               conn,
               "INSERT INTO tab(x, y) VALUES (1, 'a'), (2, 'b'), (3, 'c');",
               []
             )

    assert {:ok, res} =
             Exqlite.query(
               conn,
               "SELECT * FROM tab;",
               []
             )

    assert res |> Table.to_rows() |> Enum.to_list() == [
             %{"x" => 1, "y" => "a"},
             %{"x" => 2, "y" => "b"},
             %{"x" => 3, "y" => "c"}
           ]

    columns = Table.to_columns(res)
    assert Enum.to_list(columns["x"]) == [1, 2, 3]
    assert Enum.to_list(columns["y"]) == ["a", "b", "c"]
  end

  defp create_conn!(_) do
    opts = [database: "#{Temp.path!()}.db"]

    {:ok, pid} = start_supervised(Exqlite.child_spec(opts))

    [conn: pid]
  end
end
