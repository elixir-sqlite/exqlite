defmodule Exqlite.ExtensionsTest do
  use ExUnit.Case
  alias Exqlite.BasicAPI

  describe "enable_load_extension" do
    test "loading can be enabled / disabled" do
      {:ok, path} = Temp.path()
      {:ok, conn} = BasicAPI.open(path)
      :ok = BasicAPI.enable_load_extension(conn)

      {:ok, [[nil]], _} =
        BasicAPI.load_extension(conn, ExSqlean.path_for("re")) |> BasicAPI.rows()

      {:ok, [[1]], _} =
        BasicAPI.exec(conn, "select regexp_like('the year is 2021', '2021')")
        |> BasicAPI.rows()

      :ok = BasicAPI.disable_load_extension(conn)

      {:error, "not authorized"} =
        BasicAPI.load_extension(conn, ExSqlean.path_for("re")) |> BasicAPI.rows()
    end

    test "works for 're' (regex)" do
      {:ok, path} = Temp.path()
      {:ok, conn} = BasicAPI.open(path)

      :ok = BasicAPI.enable_load_extension(conn)

      {:ok, [[nil]], _} =
        BasicAPI.load_extension(conn, ExSqlean.path_for("re")) |> BasicAPI.rows()

      {:ok, [[0]], _} =
        BasicAPI.exec(conn, "select regexp_like('the year is 2021', '2k21')")
        |> BasicAPI.rows()

      {:ok, [[1]], _} =
        BasicAPI.exec(conn, "select regexp_like('the year is 2021', '2021')")
        |> BasicAPI.rows()
    end

    test "stats extension" do
      {:ok, path} = Temp.path()
      {:ok, conn} = BasicAPI.open(path)

      :ok = BasicAPI.enable_load_extension(conn)
      BasicAPI.load_extension(conn, ExSqlean.path_for("stats"))
      BasicAPI.load_extension(conn, ExSqlean.path_for("series"))

      {:ok, [[50.5]], ["median(value)"]} =
        BasicAPI.exec(conn, "select median(value) from generate_series(1, 100)")
        |> BasicAPI.rows()
    end
  end
end
