defmodule Exqlite.BaseTest do
  use ExUnit.Case, async: true

  # IMPORTANT: This is closely modeled on Ecto's postgres_test.exs file.
  # We strive to avoid structural differences between that file and this one.

  alias Ecto.Integration.Post
  alias Ecto.Integration.TestRepo
  alias Ecto.Migration.Table
  alias Ecto.Adapters.Exqlite.Connection, as: SQL

  import Ecto.Query

  describe "storage_up" do
    test "fails with :already_up on second call" do
      tmp = [database: tempfilename()]
      assert Exqlite.storage_up(tmp) == :ok
      assert File.exists?(tmp[:database])
      assert Exqlite.storage_up(tmp) == {:error, :already_up}
      File.rm(tmp[:database])
    end

    test "fails with helpful error message if no database specified" do
      assert_raise ArgumentError,
                   """
                   No SQLite database path specified. Please check the configuration for your Repo.
                   Your config/*.exs file should have something like this in it:

                     config :my_app, MyApp.Repo,
                       adapter: Exqlite,
                       database: "/path/to/sqlite/database"

                   Options provided were:

                   [mumble: "no database here"]

                   """,
                   fn -> Exqlite.storage_up(mumble: "no database here") == :ok end
    end
  end

  test "storage down (twice)" do
    tmp = [database: tempfilename()]
    assert Exqlite.storage_up(tmp) == :ok
    assert Exqlite.storage_down(tmp) == :ok
    refute File.exists?(tmp[:database])
    assert Exqlite.storage_down(tmp) == {:error, :already_down}
  end

  test "storage up creates directory" do
    dir = "/tmp/my_sqlite_ecto_directory/"
    File.rm_rf!(dir)
    tmp = [database: dir <> tempfilename()]
    :ok = Exqlite.storage_up(tmp)
    assert File.exists?(dir <> "tmp/") && File.dir?(dir <> "tmp/")
  end

  # return a unique temporary filename
  defp tempfilename do
    1..10
    |> Enum.map(fn _ -> :rand.uniform(10) - 1 end)
    |> Enum.join()
    |> (fn name -> "/tmp/test_" <> name <> ".db" end).()
  end

  import Ecto.Query

  alias Ecto.Queryable

  defmodule Schema do
    use Ecto.Schema

    schema "schema" do
      field(:x, :integer)
      field(:y, :integer)
      field(:z, :integer)

      has_many(:comments, Exqlite.Test.Schema2,
        references: :x,
        foreign_key: :z
      )

      has_one(:permalink, Exqlite.Test.Schema3,
        references: :y,
        foreign_key: :id
      )
    end
  end

  defmodule SchemaWithArray do
    use Ecto.Schema

    schema "schema" do
      field(:x, :integer)
      field(:y, :integer)
      field(:z, :integer)
      field(:w, {:array, :integer})
    end
  end

  defmodule Schema2 do
    use Ecto.Schema

    schema "schema2" do
      belongs_to(:post, Exqlite.Test.Schema,
        references: :x,
        foreign_key: :z
      )
    end
  end

  defmodule Schema3 do
    use Ecto.Schema

    schema "schema3" do
      field(:list1, {:array, :string})
      field(:list2, {:array, :integer})
      field(:binary, :binary)
    end
  end

  defp plan(query, operation \\ :all) do
    {query, _params} =
      Ecto.Adapter.Queryable.plan_query(operation, Ecto.Adapters.Exqlite, query)

    query
  end

  defp normalize(query, operation \\ :all, counter \\ 0) do
    {query, _params, _key} =
      Ecto.Query.Planner.prepare(query, operation, Exqlite, counter)

    {query, _} = Ecto.Query.Planner.normalize(query, operation, Exqlite, counter)
    query
  end

  defp all(query), do: query |> SQL.all() |> IO.iodata_to_binary()

  defp update_all(query),
    do: query |> SQL.update_all() |> IO.iodata_to_binary()

  defp delete_all(query),
    do: query |> SQL.delete_all() |> IO.iodata_to_binary()

  defp execute_ddl(query),
    do: query |> SQL.execute_ddl() |> Enum.map(&IO.iodata_to_binary/1)

  defp insert(prefx, table, header, rows, on_conflict, returning) do
    IO.iodata_to_binary(
      SQL.insert(prefx, table, header, rows, on_conflict, returning)
    )
  end

  defp update(prefx, table, fields, filter, returning) do
    IO.iodata_to_binary(
      SQL.update(prefx, table, fields, filter, returning)
    )
  end

  defp delete(prefx, table, filter, returning) do
    IO.iodata_to_binary(SQL.delete(prefx, table, filter, returning))
  end

  test "from" do
    query = Schema |> select([r], r.x) |> normalize
    assert all(query) == ~s{SELECT s0."x" FROM "schema" AS s0}
  end

  test "from without schema" do
    query = "posts" |> select([r], r.x) |> normalize
    assert all(query) == ~s{SELECT p0."x" FROM "posts" AS p0}

    query = "posts" |> select([:x]) |> normalize
    assert all(query) == ~s{SELECT p0."x" FROM "posts" AS p0}

    assert_raise Ecto.QueryError,
                 ~r"SQLite does not support selecting all fields from \"posts\" without a schema",
                 fn ->
                   all(from(p in "posts", select: p) |> normalize())
                 end
  end

  test "from with subquery" do
    query =
      subquery("posts" |> select([r], %{x: r.x, y: r.y}))
      |> select([r], r.x)
      |> normalize

    assert all(query) ==
             ~s{SELECT s0."x" FROM (SELECT p0."x" AS "x", p0."y" AS "y" FROM "posts" AS p0) AS s0}

    query =
      subquery("posts" |> select([r], %{x: r.x, z: r.y})) |> select([r], r) |> normalize

    assert all(query) ==
             ~s{SELECT s0."x", s0."z" FROM (SELECT p0."x" AS "x", p0."y" AS "z" FROM "posts" AS p0) AS s0}
  end

  test "select" do
    query = Schema |> select([r], {r.x, r.y}) |> normalize
    assert all(query) == ~s{SELECT s0."x", s0."y" FROM "schema" AS s0}

    query = Schema |> select([r], [r.x, r.y]) |> normalize
    assert all(query) == ~s{SELECT s0."x", s0."y" FROM "schema" AS s0}

    query = Schema |> select([r], struct(r, [:x, :y])) |> normalize
    assert all(query) == ~s{SELECT s0."x", s0."y" FROM "schema" AS s0}
  end

  test "aggregates" do
    query = Schema |> select([r], count(r.x)) |> normalize
    assert all(query) == ~s{SELECT count(s0."x") FROM "schema" AS s0}

    query = Schema |> select([r], count(r.x, :distinct)) |> normalize
    assert all(query) == ~s{SELECT count(DISTINCT s0."x") FROM "schema" AS s0}
  end

  test "distinct" do
    assert_raise ArgumentError,
                 "DISTINCT with multiple columns is not supported by SQLite",
                 fn ->
                   query =
                     Schema
                     |> distinct([r], r.x)
                     |> select([r], {r.x, r.y})
                     |> normalize

                   all(query)
                 end

    assert_raise ArgumentError,
                 "DISTINCT with multiple columns is not supported by SQLite",
                 fn ->
                   query =
                     Schema
                     |> distinct([r], desc: r.x)
                     |> select([r], {r.x, r.y})
                     |> normalize

                   all(query)
                 end

    assert_raise ArgumentError,
                 "DISTINCT with multiple columns is not supported by SQLite",
                 fn ->
                   query = Schema |> distinct([r], 2) |> select([r], r.x) |> normalize
                   all(query)
                 end

    assert_raise ArgumentError,
                 "DISTINCT with multiple columns is not supported by SQLite",
                 fn ->
                   query =
                     Schema
                     |> distinct([r], [r.x, r.y])
                     |> select([r], {r.x, r.y})
                     |> normalize

                   all(query)
                 end

    query = Schema |> distinct([r], true) |> select([r], {r.x, r.y}) |> normalize
    assert all(query) == ~s{SELECT DISTINCT s0."x", s0."y" FROM "schema" AS s0}

    query = Schema |> distinct([r], false) |> select([r], {r.x, r.y}) |> normalize
    assert all(query) == ~s{SELECT s0."x", s0."y" FROM "schema" AS s0}

    query = Schema |> distinct(true) |> select([r], {r.x, r.y}) |> normalize
    assert all(query) == ~s{SELECT DISTINCT s0."x", s0."y" FROM "schema" AS s0}

    query = Schema |> distinct(false) |> select([r], {r.x, r.y}) |> normalize
    assert all(query) == ~s{SELECT s0."x", s0."y" FROM "schema" AS s0}
  end

  test "distinct with order by" do
    assert_raise ArgumentError,
                 "DISTINCT with multiple columns is not supported by SQLite",
                 fn ->
                   query =
                     Schema
                     |> order_by([r], [r.y])
                     |> distinct([r], desc: r.x)
                     |> select([r], r.x)
                     |> normalize

                   all(query)
                 end
  end

  test "where" do
    query =
      Schema
      |> where([r], r.x == 42)
      |> where([r], r.y != 43)
      |> select([r], r.x)
      |> normalize

    assert all(query) ==
             ~s{SELECT s0."x" FROM "schema" AS s0 WHERE (s0."x" = 42) AND (s0."y" != 43)}
  end

  test "or_where" do
    query =
      Schema
      |> or_where([r], r.x == 42)
      |> or_where([r], r.y != 43)
      |> select([r], r.x)
      |> normalize

    assert all(query) ==
             ~s{SELECT s0."x" FROM "schema" AS s0 WHERE (s0."x" = 42) OR (s0."y" != 43)}

    query =
      Schema
      |> or_where([r], r.x == 42)
      |> or_where([r], r.y != 43)
      |> where([r], r.z == 44)
      |> select([r], r.x)
      |> normalize

    assert all(query) ==
             ~s{SELECT s0."x" FROM "schema" AS s0 WHERE ((s0."x" = 42) OR (s0."y" != 43)) AND (s0."z" = 44)}
  end

  test "order by" do
    query = Schema |> order_by([r], r.x) |> select([r], r.x) |> normalize
    assert all(query) == ~s{SELECT s0."x" FROM "schema" AS s0 ORDER BY s0."x"}

    query = Schema |> order_by([r], [r.x, r.y]) |> select([r], r.x) |> normalize
    assert all(query) == ~s{SELECT s0."x" FROM "schema" AS s0 ORDER BY s0."x", s0."y"}

    query =
      Schema |> order_by([r], asc: r.x, desc: r.y) |> select([r], r.x) |> normalize

    assert all(query) ==
             ~s{SELECT s0."x" FROM "schema" AS s0 ORDER BY s0."x", s0."y" DESC}

    query = Schema |> order_by([r], []) |> select([r], r.x) |> normalize
    assert all(query) == ~s{SELECT s0."x" FROM "schema" AS s0}
  end

  test "limit and offset" do
    query = Schema |> limit([r], 3) |> select([], true) |> normalize
    assert all(query) == ~s{SELECT 1 FROM "schema" AS s0 LIMIT 3}

    query = Schema |> offset([r], 5) |> select([], true) |> normalize
    assert all(query) == ~s{SELECT 1 FROM "schema" AS s0 OFFSET 5}

    query = Schema |> offset([r], 5) |> limit([r], 3) |> select([], true) |> normalize
    assert all(query) == ~s{SELECT 1 FROM "schema" AS s0 LIMIT 3 OFFSET 5}
  end

  test "lock" do
    assert_raise ArgumentError, "locks are not supported by SQLite", fn ->
      query = Schema |> lock("FOR SHARE NOWAIT") |> select([], 0) |> normalize
      all(query)
    end
  end

  test "string escape" do
    query = "schema" |> where(foo: "'\\  ") |> select([], true) |> normalize

    assert all(query) ==
             ~s{SELECT 1 FROM \"schema\" AS s0 WHERE (s0.\"foo\" = '''\\  ')}

    query = "schema" |> where(foo: "'") |> select([], true) |> normalize
    assert all(query) == ~s{SELECT 1 FROM "schema" AS s0 WHERE (s0."foo" = '''')}
  end

  test "binary ops" do
    query = Schema |> select([r], r.x == 2) |> normalize
    assert all(query) == ~s{SELECT s0."x" = 2 FROM "schema" AS s0}

    query = Schema |> select([r], r.x != 2) |> normalize
    assert all(query) == ~s{SELECT s0."x" != 2 FROM "schema" AS s0}

    query = Schema |> select([r], r.x <= 2) |> normalize
    assert all(query) == ~s{SELECT s0."x" <= 2 FROM "schema" AS s0}

    query = Schema |> select([r], r.x >= 2) |> normalize
    assert all(query) == ~s{SELECT s0."x" >= 2 FROM "schema" AS s0}

    query = Schema |> select([r], r.x < 2) |> normalize
    assert all(query) == ~s{SELECT s0."x" < 2 FROM "schema" AS s0}

    query = Schema |> select([r], r.x > 2) |> normalize
    assert all(query) == ~s{SELECT s0."x" > 2 FROM "schema" AS s0}
  end

  test "is_nil" do
    query = Schema |> select([r], is_nil(r.x)) |> normalize
    assert all(query) == ~s{SELECT s0."x" IS NULL FROM "schema" AS s0}

    query = Schema |> select([r], not is_nil(r.x)) |> normalize
    assert all(query) == ~s{SELECT NOT (s0."x" IS NULL) FROM "schema" AS s0}
  end

  test "fragments" do
    query = Schema |> select([r], fragment("ltrim(?)", r.x)) |> normalize
    assert all(query) == ~s{SELECT ltrim(s0."x") FROM "schema" AS s0}

    value = 13
    query = Schema |> select([r], fragment("ltrim(?, ?)", r.x, ^value)) |> normalize
    assert all(query) == ~s{SELECT ltrim(s0."x", ?1) FROM "schema" AS s0}

    query = Schema |> select([], fragment(title: 2)) |> normalize

    assert_raise Ecto.QueryError,
                 ~r"SQLite adapter does not support keyword or interpolated fragments",
                 fn ->
                   all(query)
                 end
  end

  test "literals" do
    query = "schema" |> where(foo: true) |> select([], true) |> normalize
    assert all(query) == ~s{SELECT 1 FROM "schema" AS s0 WHERE (s0."foo" = 1)}

    query = "schema" |> where(foo: false) |> select([], true) |> normalize
    assert all(query) == ~s{SELECT 1 FROM "schema" AS s0 WHERE (s0."foo" = 0)}

    query = "schema" |> where(foo: "abc") |> select([], true) |> normalize
    assert all(query) == ~s{SELECT 1 FROM "schema" AS s0 WHERE (s0."foo" = 'abc')}

    query = "schema" |> where(foo: <<0, ?a, ?b, ?c>>) |> select([], true) |> normalize
    assert all(query) == ~s{SELECT 1 FROM "schema" AS s0 WHERE (s0."foo" = X'00616263')}

    query = "schema" |> where(foo: 123) |> select([], true) |> normalize
    assert all(query) == ~s{SELECT 1 FROM "schema" AS s0 WHERE (s0."foo" = 123)}

    query = "schema" |> where(foo: 123.0) |> select([], true) |> normalize
    assert all(query) == ~s{SELECT 1 FROM "schema" AS s0 WHERE (s0."foo" = 123.0)}
  end

  test "tagged type" do
    query =
      Schema
      |> select([], type(^"601d74e4-a8d3-4b6e-8365-eddb4c893327", Ecto.UUID))
      |> normalize

    assert all(query) == ~s{SELECT CAST (?1 AS TEXT) FROM "schema" AS s0}

    assert_raise ArgumentError, "Array type is not supported by SQLite", fn ->
      query = Schema |> select([], type(^[1, 2, 3], {:array, :integer})) |> normalize
      all(query)
    end
  end

  test "nested expressions" do
    z = 123

    query =
      from(r in Schema, [])
      |> select([r], (r.x > 0 and r.y > ^(-z)) or true)
      |> normalize

    assert all(query) ==
             ~s{SELECT ((s0."x" > 0) AND (s0."y" > ?1)) OR 1 FROM "schema" AS s0}
  end

  test "in expression" do
    query = Schema |> select([e], 1 in []) |> normalize
    assert all(query) == ~s{SELECT 1 IN () FROM "schema" AS s0}

    query = Schema |> select([e], 1 in [1, e.x, 3]) |> normalize
    assert all(query) == ~s{SELECT 1 IN (1,s0."x",3) FROM "schema" AS s0}

    query = Schema |> select([e], 1 in ^[]) |> normalize
    assert all(query) == ~s{SELECT 1 IN () FROM "schema" AS s0}

    query = Schema |> select([e], 1 in ^[1, 2, 3]) |> normalize
    assert all(query) == ~s{SELECT 1 IN (?1,?2,?3) FROM "schema" AS s0}

    query = Schema |> select([e], 1 in [1, ^2, 3]) |> normalize
    assert all(query) == ~s{SELECT 1 IN (1,?1,3) FROM "schema" AS s0}

    query = Schema |> select([e], ^1 in [1, ^2, 3]) |> normalize
    assert all(query) == ~s{SELECT ?1 IN (1,?2,3) FROM "schema" AS s0}

    query = Schema |> select([e], ^1 in ^[1, 2, 3]) |> normalize
    assert all(query) == ~s{SELECT ?1 IN (?2,?3,?4) FROM "schema" AS s0}

    # query = Schema |> select([e], 1 in e.w) |> normalize
    # assert all(query) == ~s{SELECT 1 = ANY(s0."w") FROM "schema" AS s0}
    # This assertion omitted because we can't support array values.

    query = Schema |> select([e], 1 in fragment("foo")) |> normalize
    assert all(query) == ~s{SELECT 1 IN (foo) FROM "schema" AS s0}
  end

  test "having" do
    query = Schema |> having([p], p.x == p.x) |> select([], true) |> normalize
    assert all(query) == ~s{SELECT 1 FROM "schema" AS s0 HAVING (s0."x" = s0."x")}

    query =
      Schema
      |> having([p], p.x == p.x)
      |> having([p], p.y == p.y)
      |> select([], true)
      |> normalize

    assert all(query) ==
             ~s{SELECT 1 FROM "schema" AS s0 HAVING (s0."x" = s0."x") AND (s0."y" = s0."y")}
  end

  test "or_having" do
    query = Schema |> or_having([p], p.x == p.x) |> select([], true) |> normalize
    assert all(query) == ~s{SELECT 1 FROM "schema" AS s0 HAVING (s0."x" = s0."x")}

    query =
      Schema
      |> or_having([p], p.x == p.x)
      |> or_having([p], p.y == p.y)
      |> select([], true)
      |> normalize

    assert all(query) ==
             ~s{SELECT 1 FROM "schema" AS s0 HAVING (s0."x" = s0."x") OR (s0."y" = s0."y")}
  end

  test "group by" do
    query = Schema |> group_by([r], r.x) |> select([r], r.x) |> normalize
    assert all(query) == ~s{SELECT s0."x" FROM "schema" AS s0 GROUP BY s0."x"}

    query = Schema |> group_by([r], 2) |> select([r], r.x) |> normalize
    assert all(query) == ~s{SELECT s0."x" FROM "schema" AS s0 GROUP BY 2}

    query = Schema |> group_by([r], [r.x, r.y]) |> select([r], r.x) |> normalize
    assert all(query) == ~s{SELECT s0."x" FROM "schema" AS s0 GROUP BY s0."x", s0."y"}

    query = Schema |> group_by([r], []) |> select([r], r.x) |> normalize
    assert all(query) == ~s{SELECT s0."x" FROM "schema" AS s0}
  end

  test "arrays and sigils" do
    assert_raise ArgumentError, "Array values are not supported by SQLite", fn ->
      query = Schema |> select([], fragment("?", [1, 2, 3])) |> normalize
      all(query)
    end

    assert_raise ArgumentError, "Array values are not supported by SQLite", fn ->
      query = Schema |> select([], fragment("?", ~w(abc def))) |> normalize
      all(query)
    end
  end

  test "interpolated values" do
    cte1 = "schema1" |> select([m], %{id: m.id, smth: ^true}) |> where([], fragment("?", ^1))
    union = "schema1" |> select([m], {m.id, ^true}) |> where([], fragment("?", ^5))
    union_all = "schema2" |> select([m], {m.id, ^false}) |> where([], fragment("?", ^6))

    query = Schema
            |> with_cte("cte1", as: ^cte1)
            |> with_cte("cte2", as: fragment("SELECT * FROM schema WHERE ?", ^2))
            |> select([m], {m.id, ^0})
            |> join(:inner, [], Schema2, on: fragment("?", ^true))
            |> join(:inner, [], Schema2, on: fragment("?", ^false))
            |> where([], fragment("?", ^true))
            |> where([], fragment("?", ^false))
            |> having([], fragment("?", ^true))
            |> having([], fragment("?", ^false))
            |> group_by([], fragment("?", ^3))
            |> group_by([], fragment("?", ^4))
            |> union(^union)
            |> union_all(^union_all)
            |> order_by([], fragment("?", ^7))
            |> limit([], ^8)
            |> offset([], ^9)
            |> plan()

    result =
      "WITH cte1 AS (SELECT s0.id AS id, ? AS smth FROM schema1 AS s0 WHERE (?)), " <>
      "cte2 AS (SELECT * FROM schema WHERE ?) " <>
      "SELECT s0.id, ? FROM schema AS s0 INNER JOIN schema2 AS s1 ON ? " <>
      "INNER JOIN schema2 AS s2 ON ? WHERE (?) AND (?) " <>
      "GROUP BY ?, ? HAVING (?) AND (?) " <>
      "UNION (SELECT s0.id, ? FROM schema1 AS s0 WHERE (?)) " <>
      "UNION ALL (SELECT s0.id, ? FROM schema2 AS s0 WHERE (?)) " <>
      "ORDER BY ? LIMIT ? OFFSET ?"

    assert all(query) == String.trim(result)
  end

  test "fragments and types" do
    query =
      normalize(
        from(e in "schema",
          where:
            fragment(
              "extract(? from ?) = ?",
              ^"month",
              e.start_time,
              type(^"4", :integer)
            ),
          where:
            fragment(
              "extract(? from ?) = ?",
              ^"year",
              e.start_time,
              type(^"2015", :integer)
            ),
          select: true
        )
      )

    result =
      "SELECT 1 FROM \"schema\" AS s0 " <>
        "WHERE (extract(?1 from s0.\"start_time\") = ?2) " <>
        "AND (extract(?3 from s0.\"start_time\") = ?4)"

    assert all(query) == String.trim(result)
  end

  test "fragments allow ? to be escaped with backslash" do
    query =
      normalize(
        from(e in "schema",
          where: fragment("? = \"query\\?\"", e.start_time),
          select: true
        )
      )

    result =
      "SELECT 1 FROM \"schema\" AS s0 " <>
        "WHERE (s0.\"start_time\" = \"query?\")"

    assert all(query) == String.trim(result)
  end

  ## *_all

  test "update all" do
    query = from(m in Schema, update: [set: [x: 0]]) |> normalize(:update_all)

    assert update_all(query) ==
             ~s{UPDATE "schema" SET "x" = 0}

    query =
      from(m in Schema, update: [set: [x: 0], inc: [y: 1, z: -3]])
      |> normalize(:update_all)

    assert update_all(query) ==
             ~s{UPDATE "schema" SET "x" = 0, "y" = "schema"."y" + 1, "z" = "schema"."z" + -3}

    query =
      from(e in Schema, where: e.x == 123, update: [set: [x: 0]])
      |> normalize(:update_all)

    assert update_all(query) ==
             ~s{UPDATE "schema" SET "x" = 0 WHERE ("schema"."x" = 123)}

    query = from(m in Schema, update: [set: [x: ^0]]) |> normalize(:update_all)

    assert update_all(query) ==
             ~s{UPDATE "schema" SET "x" = ?1}

    # assert_raise ArgumentError,
    #              "JOINS are not supported on UPDATE statements by SQLite",
    #              fn ->
    #                query =
    #                  Schema
    #                  |> join(:inner, [p], q in Schema2, p.x == q.z)
    #                  |> update([_], set: [x: 0])
    #                  |> normalize(:update_all)

    #                update_all(query)
    #              end

    # assert_raise ArgumentError,
    #              "JOINS are not supported on UPDATE statements by SQLite",
    #              fn ->
    #                query =
    #                  from(e in Schema,
    #                    where: e.x == 123,
    #                    update: [set: [x: 0]],
    #                    join: q in Schema2,
    #                    on: e.x == q.z
    #                  )
    #                  |> normalize(:update_all)

    #                update_all(query)
    #              end
  end

  test "update all with returning" do
    query =
      from(m in Schema, update: [set: [x: 0]])
      |> select([m], m)
      |> normalize(:update_all)

    assert update_all(query) ==
             ~s{UPDATE "schema" SET "x" = 0 ;--RETURNING ON UPDATE "schema","id","x","y","z"}

    # diff SQLite syntax
  end

  test "update all array ops" do
    assert_raise ArgumentError, "Array operations are not supported by SQLite", fn ->
      query =
        from(m in SchemaWithArray, update: [push: [w: 0]]) |> normalize(:update_all)

      update_all(query)
    end

    assert_raise ArgumentError, "Array operations are not supported by SQLite", fn ->
      query =
        from(m in SchemaWithArray, update: [pull: [w: 0]]) |> normalize(:update_all)

      update_all(query)
    end
  end

  # new don't know what to expect
  test "update all with prefix" do
    query = from(m in Schema, update: [set: [x: 0]]) |> normalize(:update_all)

    assert update_all(%{query | prefix: "prefix"}) ==
             ~s{UPDATE "prefix"."schema" SET "x" = 0}
  end

  test "delete all" do
    query = Schema |> Queryable.to_query() |> normalize
    assert delete_all(query) == ~s{DELETE FROM "schema"}

    query = from(e in Schema, where: e.x == 123) |> normalize

    assert delete_all(query) ==
             ~s{DELETE FROM "schema" WHERE ("schema"."x" = 123)}

    # assert_raise ArgumentError,
    #              "JOINS are not supported on DELETE statements by SQLite",
    #              fn ->
    #                query =
    #                  Schema |> join(:inner, [p], q in Schema2, p.x == q.z) |> normalize

    #                delete_all(query)
    #              end

    # assert_raise ArgumentError,
    #              "JOINS are not supported on DELETE statements by SQLite",
    #              fn ->
    #                query =
    #                  from(e in Schema,
    #                    where: e.x == 123,
    #                    join: q in Schema2,
    #                    on: e.x == q.z
    #                  )
    #                  |> normalize

    #                delete_all(query)
    #              end

    # assert_raise ArgumentError,
    #              "JOINS are not supported on DELETE statements by SQLite",
    #              fn ->
    #                query =
    #                  from(e in Schema,
    #                    where: e.x == 123,
    #                    join: assoc(e, :comments),
    #                    join: assoc(e, :permalink)
    #                  )
    #                  |> normalize

    #                delete_all(query)
    #              end
  end

  test "delete all with returning" do
    query = Schema |> Queryable.to_query() |> select([m], m) |> normalize

    assert delete_all(query) ==
             ~s{DELETE FROM "schema" ;--RETURNING ON DELETE "schema","id","x","y","z"}
  end

  test "delete all with prefix" do
    query = Schema |> Queryable.to_query() |> normalize
    assert delete_all(%{query | prefix: "prefix"}) == ~s{DELETE FROM "prefix"."schema"}
  end

  ##
  ## Partitions and windows
  ##

  describe "windows" do
    test "one window" do
      query = Schema
              |> select([r], r.x)
              |> windows([r], w: [partition_by: r.x])
              |> plan

      assert all(query) == ~s{SELECT s0.x FROM schema AS s0 WINDOW w AS (PARTITION BY s0.x)}
    end

    test "two windows" do
      query = Schema
              |> select([r], r.x)
              |> windows([r], w1: [partition_by: r.x], w2: [partition_by: r.y])
              |> plan()
      assert all(query) == ~s{SELECT s0.x FROM schema AS s0 WINDOW w1 AS (PARTITION BY s0.x), w2 AS (PARTITION BY s0.y)}
    end

    test "count over window" do
      query = Schema
              |> windows([r], w: [partition_by: r.x])
              |> select([r], count(r.x) |> over(:w))
              |> plan()
      assert all(query) == ~s{SELECT count(s0.x) OVER w FROM schema AS s0 WINDOW w AS (PARTITION BY s0.x)}
    end

    test "count over all" do
      query = Schema
              |> select([r], count(r.x) |> over)
              |> plan()
      assert all(query) == ~s{SELECT count(s0.x) OVER () FROM schema AS s0}
    end

    test "row_number over all" do
      query = Schema
              |> select(row_number |> over)
              |> plan()
      assert all(query) == ~s{SELECT row_number() OVER () FROM schema AS s0}
    end

    test "nth_value over all" do
      query = Schema
              |> select([r], nth_value(r.x, 42) |> over)
              |> plan()
      assert all(query) == ~s{SELECT nth_value(s0.x, 42) OVER () FROM schema AS s0}
    end

    test "lag/2 over all" do
      query = Schema
              |> select([r], lag(r.x, 42) |> over)
              |> plan()
      assert all(query) == ~s{SELECT lag(s0.x, 42) OVER () FROM schema AS s0}
    end

    test "custom aggregation over all" do
      query = Schema
              |> select([r], fragment("custom_function(?)", r.x) |> over)
              |> plan()
      assert all(query) == ~s{SELECT custom_function(s0.x) OVER () FROM schema AS s0}
    end

    test "partition by and order by on window" do
      query = Schema
              |> windows([r], w: [partition_by: [r.x, r.z], order_by: r.x])
              |> select([r], r.x)
              |> plan()
      assert all(query) == ~s{SELECT s0.x FROM schema AS s0 WINDOW w AS (PARTITION BY s0.x, s0.z ORDER BY s0.x)}
    end

    test "partition by and order by on over" do
      query = Schema
              |> select([r], count(r.x) |> over(partition_by: [r.x, r.z], order_by: r.x))

      query = query |> plan()
      assert all(query) == ~s{SELECT count(s0.x) OVER (PARTITION BY s0.x, s0.z ORDER BY s0.x) FROM schema AS s0}
    end

    test "frame clause" do
      query = Schema
              |> select([r], count(r.x) |> over(partition_by: [r.x, r.z], order_by: r.x, frame: fragment("ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING")))

      query = query |> plan()
      assert all(query) == ~s{SELECT count(s0.x) OVER (PARTITION BY s0.x, s0.z ORDER BY s0.x ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) FROM schema AS s0}
    end
  end

  ##
  ## Joins
  ##

  test "join" do
    query = Schema |> join(:inner, [p], q in Schema2, on: p.x == q.z) |> select([], true) |> plan()
    assert all(query) ==
           ~s{SELECT TRUE FROM schema AS s0 INNER JOIN schema2 AS s1 ON s0.x = s1.z}

    query = Schema |> join(:inner, [p], q in Schema2, on: p.x == q.z)
                  |> join(:inner, [], Schema, on: true) |> select([], true) |> plan()
    assert all(query) ==
           ~s{SELECT TRUE FROM schema AS s0 INNER JOIN schema2 AS s1 ON s0.x = s1.z } <>
           ~s{INNER JOIN schema AS s2 ON TRUE}
  end

  test "join with hints" do
    assert Schema
           |> join(:inner, [p], q in Schema2, hints: ["USE INDEX FOO", "USE INDEX BAR"])
           |> select([], true)
           |> plan()
           |> all() == ~s{SELECT TRUE FROM schema AS s0 INNER JOIN schema2 AS s1 USE INDEX FOO USE INDEX BAR ON TRUE}
  end

  test "join with nothing bound" do
    query = Schema |> join(:inner, [], q in Schema2, on: q.z == q.z) |> select([], true) |> plan()
    assert all(query) ==
           ~s{SELECT TRUE FROM schema AS s0 INNER JOIN schema2 AS s1 ON s1.z = s1.z}
  end

  test "join without schema" do
    query = "posts" |> join(:inner, [p], q in "comments", on: p.x == q.z) |> select([], true) |> plan()
    assert all(query) ==
           ~s{SELECT TRUE FROM posts AS p0 INNER JOIN comments AS c1 ON p0.x = c1.z}
  end

  test "join with subquery" do
    posts = subquery("posts" |> where(title: ^"hello") |> select([r], %{x: r.x, y: r.y}))
    query = "comments" |> join(:inner, [c], p in subquery(posts), on: true) |> select([_, p], p.x) |> plan()
    assert all(query) ==
           ~s{SELECT s1.x FROM comments AS c0 } <>
           ~s{INNER JOIN (SELECT sp0.x AS x, sp0.y AS y FROM posts AS sp0 WHERE (sp0.title = ?)) AS s1 ON TRUE}

    posts = subquery("posts" |> where(title: ^"hello") |> select([r], %{x: r.x, z: r.y}))
    query = "comments" |> join(:inner, [c], p in subquery(posts), on: true) |> select([_, p], p) |> plan()
    assert all(query) ==
           ~s{SELECT s1.x, s1.z FROM comments AS c0 } <>
           ~s{INNER JOIN (SELECT sp0.x AS x, sp0.y AS z FROM posts AS sp0 WHERE (sp0.title = ?)) AS s1 ON TRUE}

    posts = subquery("posts" |> where(title: parent_as(:comment).subtitle) |> select([r], r.title))
    query = "comments" |> from(as: :comment) |> join(:inner, [c], p in subquery(posts)) |> select([_, p], p) |> plan()
    assert all(query) ==
           "SELECT s1.title FROM comments AS c0 " <>
           "INNER JOIN (SELECT sp0.title AS title FROM posts AS sp0 WHERE (sp0.title = c0.subtitle)) AS s1 ON TRUE"
  end

  test "join with prefix" do
    query = Schema |> join(:inner, [p], q in Schema2, on: p.x == q.z) |> select([], true) |> Map.put(:prefix, "prefix") |> plan()
    assert all(query) ==
           ~s{SELECT TRUE FROM prefix.schema AS s0 INNER JOIN prefix.schema2 AS s1 ON s0.x = s1.z}

    query = Schema |> from(prefix: "first") |> join(:inner, [p], q in Schema2, on: p.x == q.z, prefix: "second") |> select([], true) |> Map.put(:prefix, "prefix") |> plan()
    assert all(query) ==
           ~s{SELECT TRUE FROM first.schema AS s0 INNER JOIN second.schema2 AS s1 ON s0.x = s1.z}
  end

  test "join with fragment" do
    query = Schema
            |> join(:inner, [p], q in fragment("SELECT * FROM schema2 AS s2 WHERE s2.id = ? AND s2.field = ?", p.x, ^10))
            |> select([p], {p.id, ^0})
            |> where([p], p.id > 0 and p.id < ^100)
            |> plan()
    assert all(query) ==
           ~s{SELECT s0.id, ? FROM schema AS s0 INNER JOIN } <>
           ~s{(SELECT * FROM schema2 AS s2 WHERE s2.id = s0.x AND s2.field = ?) AS f1 ON TRUE } <>
           ~s{WHERE ((s0.id > 0) AND (s0.id < ?))}
  end

  test "join with fragment and on defined" do
    query = Schema
            |> join(:inner, [p], q in fragment("SELECT * FROM schema2"), on: q.id == p.id)
            |> select([p], {p.id, ^0})
            |> plan()
    assert all(query) ==
           ~s{SELECT s0.id, ? FROM schema AS s0 INNER JOIN } <>
           ~s{(SELECT * FROM schema2) AS f1 ON f1.id = s0.id}
  end

  test "join with query interpolation" do
    inner = Ecto.Queryable.to_query(Schema2)
    query = from(p in Schema, left_join: c in ^inner, select: {p.id, c.id}) |> plan()
    assert all(query) ==
           "SELECT s0.id, s1.id FROM schema AS s0 LEFT OUTER JOIN schema2 AS s1 ON TRUE"
  end

  test "cross join" do
    query = from(p in Schema, cross_join: c in Schema2, select: {p.id, c.id}) |> plan()
    assert all(query) ==
           "SELECT s0.id, s1.id FROM schema AS s0 CROSS JOIN schema2 AS s1"
  end

  test "join produces correct bindings" do
    query = from(p in Schema, join: c in Schema2, on: true)
    query = from(p in query, join: c in Schema2, on: true, select: {p.id, c.id})
    query = plan(query)
    assert all(query) ==
           "SELECT s0.id, s2.id FROM schema AS s0 INNER JOIN schema2 AS s1 ON TRUE INNER JOIN schema2 AS s2 ON TRUE"
  end

  ## Associations

  test "association join belongs_to" do
    query =
      Schema2
      |> join(:inner, [c], p in assoc(c, :post))
      |> select([], true)
      |> normalize

    assert all(query) ==
             "SELECT 1 FROM \"schema2\" AS s0 INNER JOIN \"schema\" AS s1 ON s1.\"x\" = s0.\"z\""
  end

  test "association join has_many" do
    query =
      Schema
      |> join(:inner, [p], c in assoc(p, :comments))
      |> select([], true)
      |> normalize

    assert all(query) ==
             "SELECT 1 FROM \"schema\" AS s0 INNER JOIN \"schema2\" AS s1 ON s1.\"z\" = s0.\"x\""
  end

  test "association join has_one" do
    query =
      Schema
      |> join(:inner, [p], pp in assoc(p, :permalink))
      |> select([], true)
      |> normalize

    assert all(query) ==
             "SELECT 1 FROM \"schema\" AS s0 INNER JOIN \"schema3\" AS s1 ON s1.\"id\" = s0.\"y\""
  end

  # Schema based

  test "insert" do
    query = insert(nil, "schema", [:x, :y], [[:x, :y]], {:raise, [], []}, [:id])

    assert query ==
             ~s{INSERT INTO "schema" ("x","y") VALUES (?1,?2) ;--RETURNING ON INSERT "schema","id"}

    assert_raise ArgumentError,
                 "Cell-wise default values are not supported on INSERT statements by SQLite",
                 fn ->
                   insert(
                     nil,
                     "schema",
                     [:x, :y],
                     [[:x, :y], [nil, :z]],
                     {:raise, [], []},
                     [:id]
                   )
                 end

    query = insert(nil, "schema", [], [[]], {:raise, [], []}, [:id])

    assert query ==
             ~s{INSERT INTO "schema" DEFAULT VALUES ;--RETURNING ON INSERT "schema","id"}

    query = insert(nil, "schema", [], [[]], {:raise, [], []}, [])
    assert query == ~s{INSERT INTO "schema" DEFAULT VALUES}

    query = insert("prefix", "schema", [], [[]], {:raise, [], []}, [:id])

    assert query ==
             ~s{INSERT INTO "prefix"."schema" DEFAULT VALUES ;--RETURNING ON INSERT "prefix"."schema","id"}

    query = insert("prefix", "schema", [], [[]], {:raise, [], []}, [])
    assert query == ~s{INSERT INTO "prefix"."schema" DEFAULT VALUES}
  end

  test "insert with on conflict" do
    # These tests are adapted from the Postgres Adaptor

    # For :nothing
    query = insert(nil, "schema", [:x, :y], [[:x, :y]], {:nothing, [], []}, [])

    assert query ==
             ~s{INSERT INTO "schema" ("x","y") VALUES (?1,?2) ON CONFLICT DO NOTHING}

    query = insert(nil, "schema", [:x, :y], [[:x, :y]], {:nothing, [], [:x, :y]}, [])

    assert query ==
             ~s{INSERT INTO "schema" ("x","y") VALUES (?1,?2) ON CONFLICT ("x","y") DO NOTHING}

    # For :update
    update = from("schema", update: [set: [z: "foo"]]) |> normalize(:update_all)
    query = insert(nil, "schema", [:x, :y], [[:x, :y]], {update, [], [:x, :y]}, [:z])

    assert query ==
             ~s{INSERT INTO "schema" ("x","y") VALUES (?1,?2) ON CONFLICT ("x","y") DO UPDATE SET "z" = 'foo' ;--RETURNING ON INSERT "schema","z"}

    update =
      from("schema", update: [set: [z: ^"foo"]], where: [w: true])
      |> normalize(:update_all, 2)

    query = insert(nil, "schema", [:x, :y], [[:x, :y]], {update, [], [:x, :y]}, [:z])

    assert query =
             ~s{INSERT INTO "schema" ("x","y") VALUES (?1,?2) ON CONFLICT ("x","y") DO UPDATE SET "z" = ?3 WHERE ("schema"."w" = 1) ;--RETURNING ON INSERT "schema","z"}

    update = normalize(from("schema", update: [set: [z: "foo"]]), :update_all)
    query = insert(nil, "schema", [:x, :y], [[:x, :y]], {update, [], [:x, :y]}, [:z])

    assert query =
             ~s{INSERT INTO "schema" ("x","y") VALUES (?1,?2) ON CONFLICT ("x","y") DO UPDATE SET "z" = 'foo' ;--RETURNING ON INSERT "schema","z"}

    update =
      normalize(
        from("schema", update: [set: [z: ^"foo"]], where: [w: true]),
        :update_all,
        2
      )

    query = insert(nil, "schema", [:x, :y], [[:x, :y]], {update, [], [:x, :y]}, [:z])

    assert query =
             ~s{INSERT INTO "schema" ("x","y") VALUES (?1,?2) ON CONFLICT ("x","y") DO UPDATE SET "z" = ?3 WHERE ("schema"."w" = 1) ;--RETURNING ON INSERT "schema","z"}

    # For :replace_all
    assert_raise ArgumentError, "Upsert in SQLite requires :conflict_target", fn ->
      conflict_target = []

      insert(
        nil,
        "schema",
        [:x, :y],
        [[:x, :y]],
        {:replace_all, [], conflict_target},
        []
      )
    end

    assert_raise ArgumentError, "Upsert in SQLite does not support ON CONSTRAINT", fn ->
      insert(
        nil,
        "schema",
        [:x, :y],
        [[:x, :y]],
        {:replace_all, [], {:constraint, :foo}},
        []
      )
    end

    query = insert(nil, "schema", [:x, :y], [[:x, :y]], {:replace_all, [], [:id]}, [])

    assert query ==
             ~s{INSERT INTO "schema" ("x","y") VALUES (?1,?2) ON CONFLICT ("id") DO UPDATE SET "x" = EXCLUDED."x","y" = EXCLUDED."y"}
  end

  test "update" do
    query = update(nil, "schema", [:x, :y], [:id], [])
    assert query == ~s{UPDATE "schema" SET "x" = ?1, "y" = ?2 WHERE "id" = ?3}

    query = update(nil, "schema", [:x, :y], [:id], [:z])

    assert query ==
             ~s{UPDATE "schema" SET "x" = ?1, "y" = ?2 WHERE "id" = ?3 ;--RETURNING ON UPDATE "schema","z"}

    query = update("prefix", "schema", [:x, :y], [:id], [:x, :z])

    assert query ==
             ~s{UPDATE "prefix"."schema" SET "x" = ?1, "y" = ?2 WHERE "id" = ?3 ;--RETURNING ON UPDATE "prefix"."schema","x","z"}

    query = update("prefix", "schema", [:x, :y], [:id], [])
    assert query == ~s{UPDATE "prefix"."schema" SET "x" = ?1, "y" = ?2 WHERE "id" = ?3}
  end

  test "delete" do
    query = delete(nil, "schema", [:x, :y], [])
    assert query == ~s{DELETE FROM "schema" WHERE "x" = ?1 AND "y" = ?2}

    query = delete(nil, "schema", [:x, :y], [:z])

    assert query ==
             ~s{DELETE FROM "schema" WHERE "x" = ?1 AND "y" = ?2 ;--RETURNING ON DELETE "schema","z"}

    query = delete("prefix", "schema", [:x, :y], [:z])

    assert query ==
             ~s{DELETE FROM "prefix"."schema" WHERE "x" = ?1 AND "y" = ?2 ;--RETURNING ON DELETE "prefix"."schema","z"}

    query = delete(nil, "schema", [:x, :y], [])
    assert query == ~s{DELETE FROM "schema" WHERE "x" = ?1 AND "y" = ?2}

    query = delete("prefix", "schema", [:x, :y], [])
    assert query == ~s{DELETE FROM "prefix"."schema" WHERE "x" = ?1 AND "y" = ?2}
  end

  # DDL

  alias Ecto.Migration.Reference

  import Ecto.Migration,
    only: [table: 1, table: 2, index: 2, index: 3, constraint: 2, constraint: 3]

  test "executing a string during migration" do
    assert execute_ddl("example") == ["example"]
  end

  test "keyword list during migration" do
    assert_raise ArgumentError,
                 "SQLite adapter does not support keyword lists in execute",
                 fn ->
                   execute_ddl(testing: false)
                 end
  end

  test "create table" do
    create =
      {:create, table(:posts),
       [
         {:add, :name, :string, [default: "Untitled", size: 20, null: false]},
         {:add, :price, :numeric,
          [precision: 8, scale: 2, default: {:fragment, "expr"}]},
         {:add, :on_hand, :integer, [default: 0, null: true]},
         {:add, :is_active, :boolean, [default: true]}
       ]}

    assert execute_ddl(create) == [
             """
             CREATE TABLE "posts" ("name" TEXT DEFAULT 'Untitled' NOT NULL,
             "price" NUMERIC DEFAULT expr,
             "on_hand" INTEGER DEFAULT 0,
             "is_active" BOOLEAN DEFAULT 1)
             """
             |> remove_newlines
           ]
  end

  test "create table invalid default" do
    create =
      {:create, table(:posts), [{:add, :name, :string, [default: :atoms_not_allowed]}]}

    assert_raise ArgumentError,
                 ~r"unknown default :atoms_not_allowed for type :string",
                 fn ->
                   execute_ddl(create)
                 end
  end

  test "create table array type" do
    create = {:create, table(:posts), [{:add, :name, {:array, :numeric}, []}]}

    assert execute_ddl(create) == [
             """
             CREATE TABLE "posts" ("name" JSON)
             """
             |> remove_newlines()
           ]
  end

  test "create table illegal options" do
    create =
      {:create, table(:posts, options: [allowed: :not]), [{:add, :name, :string}]}

    assert_raise ArgumentError,
                 ~r"SQLite adapter does not support keyword lists in :options",
                 fn ->
                   execute_ddl(create)
                 end
  end

  test "create table if not exists" do
    create =
      {:create_if_not_exists, table(:posts),
       [
         {:add, :id, :serial, [primary_key: true]},
         {:add, :title, :string, []},
         {:add, :price, :decimal, [precision: 10, scale: 2]},
         {:add, :created_at, :datetime, []}
       ]}

    query = execute_ddl(create)

    assert query == [
             """
             CREATE TABLE IF NOT EXISTS "posts" ("id" INTEGER PRIMARY KEY AUTOINCREMENT,
             "title" TEXT,
             "price" DECIMAL(10,2),
             "created_at" DATETIME)
             """
             |> remove_newlines
           ]
  end

  test "create table with prefix" do
    create =
      {:create, table(:posts, prefix: :foo),
       [{:add, :category_0, %Reference{table: :categories}, []}]}

    assert execute_ddl(create) == [
             """
             CREATE TABLE "foo"."posts"
             ("category_0" INTEGER CONSTRAINT "posts_category_0_fkey" REFERENCES "foo"."categories"("id"))
             """
             |> remove_newlines
           ]
  end

  test "create table with comment on columns and table" do
    create =
      {:create, table(:posts, comment: "comment"),
       [
         {:add, :category_0, %Reference{table: :categories},
          [comment: "column comment"]},
         {:add, :created_at, :timestamp, []},
         {:add, :updated_at, :timestamp, [comment: "column comment 2"]}
       ]}

    assert execute_ddl(create) == [
             remove_newlines("""
             CREATE TABLE "posts"
             ("category_0" INTEGER CONSTRAINT "posts_category_0_fkey" REFERENCES "categories"("id"), "created_at" TIMESTAMP, "updated_at" TIMESTAMP)
             """)
           ]

    # NOTE: Comments are not supported by SQLite. DDL query generator will ignore them.
  end

  test "create table with comment on table" do
    create =
      {:create, table(:posts, comment: "table comment"),
       [{:add, :category_0, %Reference{table: :categories}, []}]}

    assert execute_ddl(create) == [
             remove_newlines("""
             CREATE TABLE "posts"
             ("category_0" INTEGER CONSTRAINT "posts_category_0_fkey" REFERENCES "categories"("id"))
             """)
           ]

    # NOTE: Comments are not supported by SQLite. DDL query generator will ignore them.
  end

  test "create table with comment on columns" do
    create =
      {:create, table(:posts),
       [
         {:add, :category_0, %Reference{table: :categories},
          [comment: "column comment"]},
         {:add, :created_at, :timestamp, []},
         {:add, :updated_at, :timestamp, [comment: "column comment 2"]}
       ]}

    assert execute_ddl(create) == [
             remove_newlines("""
             CREATE TABLE "posts"
             ("category_0" INTEGER CONSTRAINT "posts_category_0_fkey" REFERENCES "categories"("id"), "created_at" TIMESTAMP, "updated_at" TIMESTAMP)
             """)
           ]

    # NOTE: Comments are not supported by SQLite. DDL query generator will ignore them.
  end

  test "create table with references" do
    create =
      {:create, table(:posts),
       [
         {:add, :id, :serial, [primary_key: true]},
         {:add, :category_0, %Reference{table: :categories}, []},
         {:add, :category_1, %Reference{table: :categories, name: :foo_bar}, []},
         {:add, :category_2, %Reference{table: :categories, on_delete: :nothing}, []},
         {:add, :category_3, %Reference{table: :categories, on_delete: :delete_all},
          [null: false]},
         {:add, :category_4, %Reference{table: :categories, on_delete: :nilify_all},
          []},
         {:add, :category_5, %Reference{table: :categories, on_update: :nothing}, []},
         {:add, :category_6, %Reference{table: :categories, on_update: :update_all},
          [null: false]},
         {:add, :category_7, %Reference{table: :categories, on_update: :nilify_all},
          []},
         {:add, :category_8,
          %Reference{
            table: :categories,
            on_delete: :nilify_all,
            on_update: :update_all
          }, [null: false]}
       ]}

    assert execute_ddl(create) == [
             """
             CREATE TABLE "posts" ("id" INTEGER PRIMARY KEY AUTOINCREMENT,
             "category_0" INTEGER CONSTRAINT "posts_category_0_fkey" REFERENCES "categories"("id"),
             "category_1" INTEGER CONSTRAINT "foo_bar" REFERENCES "categories"("id"),
             "category_2" INTEGER CONSTRAINT "posts_category_2_fkey" REFERENCES "categories"("id"),
             "category_3" INTEGER NOT NULL CONSTRAINT "posts_category_3_fkey" REFERENCES "categories"("id") ON DELETE CASCADE,
             "category_4" INTEGER CONSTRAINT "posts_category_4_fkey" REFERENCES "categories"("id") ON DELETE SET NULL,
             "category_5" INTEGER CONSTRAINT "posts_category_5_fkey" REFERENCES "categories"("id"),
             "category_6" INTEGER NOT NULL CONSTRAINT "posts_category_6_fkey" REFERENCES "categories"("id") ON UPDATE CASCADE,
             "category_7" INTEGER CONSTRAINT "posts_category_7_fkey" REFERENCES "categories"("id") ON UPDATE SET NULL,
             "category_8" INTEGER NOT NULL CONSTRAINT "posts_category_8_fkey" REFERENCES "categories"("id") ON DELETE SET NULL ON UPDATE CASCADE)
             """
             |> remove_newlines
           ]
  end

  test "create table with references including prefixes" do
    create =
      {:create, table(:posts, prefix: :foo),
       [
         {:add, :id, :serial, [primary_key: true]},
         {:add, :category_0, %Reference{table: :categories}, []},
         {:add, :category_1, %Reference{table: :categories, name: :foo_bar}, []},
         {:add, :category_2, %Reference{table: :categories, on_delete: :nothing}, []},
         {:add, :category_3, %Reference{table: :categories, on_delete: :delete_all},
          [null: false]},
         {:add, :category_4, %Reference{table: :categories, on_delete: :nilify_all}, []}
       ]}

    assert execute_ddl(create) == [
             """
             CREATE TABLE "foo"."posts" ("id" INTEGER PRIMARY KEY AUTOINCREMENT,
             "category_0" INTEGER CONSTRAINT "posts_category_0_fkey" REFERENCES "foo"."categories"("id"),
             "category_1" INTEGER CONSTRAINT "foo_bar" REFERENCES "foo"."categories"("id"),
             "category_2" INTEGER CONSTRAINT "posts_category_2_fkey" REFERENCES "foo"."categories"("id"),
             "category_3" INTEGER NOT NULL CONSTRAINT "posts_category_3_fkey" REFERENCES "foo"."categories"("id") ON DELETE CASCADE,
             "category_4" INTEGER CONSTRAINT "posts_category_4_fkey" REFERENCES "foo"."categories"("id") ON DELETE SET NULL)
             """
             |> remove_newlines
           ]
  end

  test "create table with options" do
    create =
      {:create, table(:posts, options: "WITHOUT ROWID"),
       [{:add, :id, :serial, [primary_key: true]}, {:add, :created_at, :datetime, []}]}

    assert execute_ddl(create) ==
             [
               ~s|CREATE TABLE "posts" ("id" INTEGER PRIMARY KEY AUTOINCREMENT, "created_at" DATETIME) WITHOUT ROWID|
             ]
  end

  test "create table with composite key" do
    create =
      {:create, table(:posts),
       [
         {:add, :a, :integer, [primary_key: true]},
         {:add, :b, :integer, [primary_key: true]},
         {:add, :name, :string, []}
       ]}

    assert execute_ddl(create) == [
             """
             CREATE TABLE "posts" ("a" INTEGER, "b" INTEGER, "name" TEXT, PRIMARY KEY ("a", "b"))
             """
             |> remove_newlines
           ]
  end

  test "create table with bad table name" do
    assert_raise ArgumentError, "bad table name \"po\\\"sts\"", fn ->
      create =
        {:create, table(:"po\"sts"),
         [{:add, :id, :serial, [primary_key: true]}, {:add, :created_at, :datetime, []}]}

      execute_ddl(create)
    end
  end

  test "create table with bad column name" do
    assert_raise ArgumentError, "bad field name \"crea\\\"ted_at\"", fn ->
      create =
        {:create, table(:posts),
         [
           {:add, :id, :serial, [primary_key: true]},
           {:add, :"crea\"ted_at", :datetime, []}
         ]}

      execute_ddl(create)
    end
  end

  test "create table with a map column, and an empty map default" do
    create =
      {:create, table(:posts),
       [
         {:add, :a, :map, [default: %{}]}
       ]}

    assert execute_ddl(create) == [~s|CREATE TABLE "posts" ("a" TEXT DEFAULT '{}')|]
  end

  test "create table with a map column, and a map default with values" do
    create =
      {:create, table(:posts),
       [
         {:add, :a, :map, [default: %{foo: "bar", baz: "boom"}]}
       ]}

    assert execute_ddl(create) == [
             ~s|CREATE TABLE "posts" ("a" TEXT DEFAULT '{"foo":"bar","baz":"boom"}')|
           ]
  end

  test "create table with a map column, and a string default" do
    create =
      {:create, table(:posts),
       [
         {:add, :a, :map, [default: ~s|{"foo":"bar","baz":"boom"}|]}
       ]}

    assert execute_ddl(create) == [
             ~s|CREATE TABLE "posts" ("a" TEXT DEFAULT '{"foo":"bar","baz":"boom"}')|
           ]
  end

  test "drop table" do
    drop = {:drop, table(:posts)}
    assert execute_ddl(drop) == [~s|DROP TABLE "posts"|]
  end

  test "drop table if exists" do
    assert execute_ddl({:drop_if_exists, %Table{name: "posts"}}) == [
             ~s|DROP TABLE IF EXISTS "posts"|
           ]
  end

  test "drop table with prefix" do
    drop = {:drop, table(:posts, prefix: :foo)}
    assert execute_ddl(drop) == [~s|DROP TABLE "foo"."posts"|]
  end

  test "alter table" do
    alter =
      {:alter, table(:posts),
       [
         {:add, :title, :string, [default: "Untitled", size: 100, null: false]},
         {:add, :author_id, %Reference{table: :author}, []}
       ]}

    assert execute_ddl(alter) == [
             remove_newlines(
               ~s|ALTER TABLE "posts" ADD COLUMN "title" TEXT DEFAULT 'Untitled' NOT NULL|
             ),
             remove_newlines(
               ~s|ALTER TABLE "posts" ADD COLUMN "author_id" INTEGER CONSTRAINT "posts_author_id_fkey" REFERENCES "author"("id")|
             )
           ]
  end

  test "alter table with datetime not null" do
    alter =
      {:alter, table(:posts),
       [
         {:add, :title, :string, [default: "Untitled", size: 100, null: false]},
         {:add, :when, :utc_datetime, [null: false]}
       ]}

    assert execute_ddl(alter) == [
             remove_newlines(
               ~s|ALTER TABLE "posts" ADD COLUMN "title" TEXT DEFAULT 'Untitled' NOT NULL|
             ),
             remove_newlines(~s|ALTER TABLE "posts" ADD COLUMN "when" UTC_DATETIME|)
           ]
  end

  test "alter table with prefix" do
    alter =
      {:alter, table(:posts, prefix: :foo),
       [
         {:add, :title, :string, [default: "Untitled", size: 100, null: false]},
         {:add, :author_id, %Reference{table: :author}, []}
       ]}

    assert execute_ddl(alter) == [
             remove_newlines(
               ~s|ALTER TABLE "foo"."posts" ADD COLUMN "title" TEXT DEFAULT 'Untitled' NOT NULL|
             ),
             remove_newlines(
               ~s|ALTER TABLE "foo"."posts" ADD COLUMN "author_id" INTEGER CONSTRAINT "posts_author_id_fkey" REFERENCES "foo"."author"("id")|
             )
           ]
  end

  test "alter column errors for :modify column" do
    alter =
      {:alter, table(:posts), [{:modify, :price, :numeric, [precision: 8, scale: 2]}]}

    assert_raise ArgumentError, "ALTER COLUMN not supported by SQLite", fn ->
      execute_ddl(alter)
    end
  end

  test "alter column errors for :remove column" do
    alter =
      {:alter, table(:posts), [{:remove, :price, :numeric, [precision: 8, scale: 2]}]}

    assert_raise ArgumentError, "ALTER COLUMN not supported by SQLite", fn ->
      execute_ddl(alter)
    end
  end

  test "alter table with primary key" do
    alter = {:alter, table(:posts), [{:add, :my_pk, :serial, [primary_key: true]}]}

    assert execute_ddl(alter) == [
             """
             ALTER TABLE "posts"
             ADD COLUMN "my_pk" INTEGER PRIMARY KEY AUTOINCREMENT
             """
             |> remove_newlines
           ]
  end

  test "create index" do
    create = {:create, index(:posts, [:category_id, :permalink])}

    assert execute_ddl(create) ==
             [
               ~s|CREATE INDEX "posts_category_id_permalink_index" ON "posts" ("category_id", "permalink")|
             ]

    create = {:create, index(:posts, ["lower(permalink)"], name: "postsmain")}

    assert execute_ddl(create) ==
             [~s|CREATE INDEX "postsmain" ON "posts" (lower(permalink))|]
  end

  test "create index if not exists" do
    create = {:create_if_not_exists, index(:posts, [:category_id, :permalink])}
    query = execute_ddl(create)

    assert query == [
             ~s|CREATE INDEX IF NOT EXISTS "posts_category_id_permalink_index" ON "posts" ("category_id", "permalink")|
           ]
  end

  test "create index with prefix" do
    create = {:create, index(:posts, [:category_id, :permalink], prefix: :foo)}

    assert execute_ddl(create) ==
             [
               ~s|CREATE INDEX "posts_category_id_permalink_index" ON "foo"."posts" ("category_id", "permalink")|
             ]

    create =
      {:create, index(:posts, ["lower(permalink)"], name: "postsmain", prefix: :foo)}

    assert execute_ddl(create) ==
             [~s|CREATE INDEX "postsmain" ON "foo"."posts" (lower(permalink))|]
  end

  test "create index with comment" do
    create =
      {:create,
       index(:posts, [:category_id, :permalink], prefix: :foo, comment: "comment")}

    assert execute_ddl(create) == [
             remove_newlines("""
             CREATE INDEX "posts_category_id_permalink_index" ON "foo"."posts" ("category_id", "permalink")
             """)
           ]

    # NOTE: Comments are not supported by SQLite. DDL query generator will ignore them.
  end

  test "create unique index" do
    create = {:create, index(:posts, [:permalink], unique: true)}

    assert execute_ddl(create) ==
             [~s|CREATE UNIQUE INDEX "posts_permalink_index" ON "posts" ("permalink")|]
  end

  test "create unique index if not exists" do
    create = {:create_if_not_exists, index(:posts, [:permalink], unique: true)}
    query = execute_ddl(create)

    assert query == [
             ~s|CREATE UNIQUE INDEX IF NOT EXISTS "posts_permalink_index" ON "posts" ("permalink")|
           ]
  end

  test "create unique index with condition" do
    create = {:create, index(:posts, [:permalink], unique: true, where: "public IS 1")}

    assert execute_ddl(create) ==
             [
               ~s|CREATE UNIQUE INDEX "posts_permalink_index" ON "posts" ("permalink") WHERE public IS 1|
             ]

    create = {:create, index(:posts, [:permalink], unique: true, where: :public)}

    assert execute_ddl(create) ==
             [
               ~s|CREATE UNIQUE INDEX "posts_permalink_index" ON "posts" ("permalink") WHERE public|
             ]
  end

  test "create index concurrently" do
    # NOTE: SQLite doesn't support CONCURRENTLY, so this isn't included in generated SQL.
    create = {:create, index(:posts, [:permalink], concurrently: true)}

    assert execute_ddl(create) ==
             [~s|CREATE INDEX "posts_permalink_index" ON "posts" ("permalink")|]
  end

  test "create unique index concurrently" do
    # NOTE: SQLite doesn't support CONCURRENTLY, so this isn't included in generated SQL.
    create = {:create, index(:posts, [:permalink], concurrently: true, unique: true)}

    assert execute_ddl(create) ==
             [~s|CREATE UNIQUE INDEX "posts_permalink_index" ON "posts" ("permalink")|]
  end

  test "create an index using a different type" do
    # NOTE: SQLite doesn't support USING, so this isn't included in generated SQL.
    create = {:create, index(:posts, [:permalink], using: :hash)}

    assert execute_ddl(create) ==
             [~s|CREATE INDEX "posts_permalink_index" ON "posts" ("permalink")|]
  end

  test "drop index" do
    drop = {:drop, index(:posts, [:id], name: "postsmain")}
    assert execute_ddl(drop) == [~s|DROP INDEX "postsmain"|]
  end

  test "drop index with prefix" do
    drop = {:drop, index(:posts, [:id], name: "postsmain", prefix: :foo)}
    assert execute_ddl(drop) == [~s|DROP INDEX "foo"."postsmain"|]
  end

  test "drop index if exists" do
    drop = {:drop_if_exists, index(:posts, [:id], name: "postsmain")}
    assert execute_ddl(drop) == [~s|DROP INDEX IF EXISTS "postsmain"|]
  end

  test "drop index concurrently" do
    # NOTE: SQLite doesn't support CONCURRENTLY, so this isn't included in generated SQL.
    drop = {:drop, index(:posts, [:id], name: "postsmain", concurrently: true)}
    assert execute_ddl(drop) == [~s|DROP INDEX "postsmain"|]
  end

  test "create check constraint" do
    create =
      {:create, constraint(:products, "price_must_be_positive", check: "price > 0")}

    assert_raise ArgumentError,
                 "ALTER TABLE with constraints not supported by SQLite",
                 fn ->
                   execute_ddl(create)
                 end

    create =
      {:create,
       constraint(:products, "price_must_be_positive", check: "price > 0", prefix: "foo")}

    assert_raise ArgumentError,
                 "ALTER TABLE with constraints not supported by SQLite",
                 fn ->
                   execute_ddl(create)
                 end
  end

  test "create exclusion constraint" do
    create =
      {:create,
       constraint(:products, "price_must_be_positive",
         exclude: ~s|gist (int4range("from", "to", '[]') WITH &&)|
       )}

    assert_raise ArgumentError,
                 "ALTER TABLE with constraints not supported by SQLite",
                 fn ->
                   execute_ddl(create)
                 end
  end

  test "create constraint with comment" do
    assert_raise ArgumentError,
                 "ALTER TABLE with constraints not supported by SQLite",
                 fn ->
                   create =
                     {:create,
                      constraint(:products, "price_must_be_positive",
                        check: "price > 0",
                        prefix: "foo",
                        comment: "comment"
                      )}

                   execute_ddl(create)
                 end
  end

  test "drop constraint" do
    drop = {:drop, constraint(:products, "price_must_be_positive")}

    assert_raise ArgumentError,
                 "ALTER TABLE with constraints not supported by SQLite",
                 fn ->
                   execute_ddl(drop)
                 end

    drop = {:drop, constraint(:products, "price_must_be_positive", prefix: "foo")}

    assert_raise ArgumentError,
                 "ALTER TABLE with constraints not supported by SQLite",
                 fn ->
                   execute_ddl(drop)
                 end
  end

  test "rename table" do
    rename = {:rename, table(:posts), table(:new_posts)}
    assert execute_ddl(rename) == [~s|ALTER TABLE "posts" RENAME TO "new_posts"|]
  end

  test "rename table with prefix" do
    rename = {:rename, table(:posts, prefix: :foo), table(:new_posts, prefix: :foo)}
    assert execute_ddl(rename) == [~s|ALTER TABLE "foo"."posts" RENAME TO "new_posts"|]
  end

  test "rename column" do
    rename = {:rename, table(:posts), :given_name, :first_name}

    assert execute_ddl(rename) == [
             ~s|ALTER TABLE "posts" RENAME COLUMN "given_name" TO "first_name"|
           ]
  end

  test "rename column in prefixed table" do
    rename = {:rename, table(:posts, prefix: :foo), :given_name, :first_name}

    assert execute_ddl(rename) == [
             ~s|ALTER TABLE "foo"."posts" RENAME COLUMN "given_name" TO "first_name"|
           ]
  end

  test "drop column errors" do
    alter = {:alter, table(:posts), [{:remove, :summary}]}

    assert_raise ArgumentError, "DROP COLUMN not supported by SQLite", fn ->
      execute_ddl(alter)
    end
  end

  test "datetime_add with microsecond" do
    assert_raise ArgumentError,
                 "SQLite does not support microsecond precision in datetime intervals",
                 fn ->
                   TestRepo.all(
                     from(p in Post,
                       select: datetime_add(p.inserted_at, 1500, "microsecond")
                     )
                   )
                 end
  end

  test "stream error handling" do
    opts = [database: ":memory:", backoff_type: :stop]
    {:ok, pid} = DBConnection.start_link(Exqlite.Protocol, opts)

    query = %Exqlite.Query{name: "", statement: "CREATE TABLE uniques (a int UNIQUE)"}
    {:ok, _, _} = DBConnection.prepare_execute(pid, query, [])

    query = %Exqlite.Query{name: "", statement: "INSERT INTO uniques VALUES(1)"}
    {:ok, _, _} = DBConnection.prepare_execute(pid, query, [])

    assert_raise Exqlite.Error, "UNIQUE constraint failed: uniques.a", fn ->
      pid
      |> SQL.stream("INSERT INTO uniques VALUES(1)", [], [])
      |> Enum.to_list()
    end
  end

  defp remove_newlines(string) do
    string |> String.trim() |> String.replace("\n", " ")
  end
end
