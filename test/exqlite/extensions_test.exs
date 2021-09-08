defmodule Exqlite.ExtensionsTest do
  use ExUnit.Case
  alias Exqlite.Basic

  describe "enable_load_extension" do
    test "loading can be enabled / disabled" do
      {:ok, path} = Temp.path()
      {:ok, conn} = Basic.open(path)
      :ok = Basic.enable_load_extension(conn)

      {:ok, [[nil]], _} =
        Basic.load_extension(conn, ExSqlean.path_for("re")) |> Basic.rows()

      {:ok, [[1]], _} =
        Basic.exec(conn, "select regexp_like('the year is 2021', '2021')")
        |> Basic.rows()

      :ok = Basic.disable_load_extension(conn)

      {:error, "not authorized"} =
        Basic.load_extension(conn, ExSqlean.path_for("re")) |> Basic.rows()
    end

    test "works for 're' (regex)" do
      {:ok, path} = Temp.path()
      {:ok, conn} = Basic.open(path)

      :ok = Basic.enable_load_extension(conn)

      {:ok, [[nil]], _} =
        Basic.load_extension(conn, ExSqlean.path_for("re")) |> Basic.rows()

      {:ok, [[0]], _} =
        Basic.exec(conn, "select regexp_like('the year is 2021', '2k21')")
        |> Basic.rows()

      {:ok, [[1]], _} =
        Basic.exec(conn, "select regexp_like('the year is 2021', '2021')")
        |> Basic.rows()
    end

    test "stats extension" do
      {:ok, path} = Temp.path()
      {:ok, conn} = Basic.open(path)

      :ok = Basic.enable_load_extension(conn)
      Basic.load_extension(conn, ExSqlean.path_for("stats"))
      Basic.load_extension(conn, ExSqlean.path_for("series"))

      {:ok, [[50.5]], ["median(value)"]} =
        Basic.exec(conn, "select median(value) from generate_series(1, 100)")
        |> Basic.rows()
    end
  end
end
