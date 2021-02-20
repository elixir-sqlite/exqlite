defmodule Ecto.Adapters.ExqliteTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Ecto.Queryable
  alias Ecto.Adapters.Exqlite.Connection, as: Connection
  alias Ecto.Migration.Reference

  ##
  ## Schema Definitions
  ##

  defmodule Schema do
    use Ecto.Schema

    schema "schema" do
      field(:x, :integer)
      field(:y, :integer)
      field(:z, :integer)
      field(:meta, :map)

      has_many(:comments, Ecto.Adapters.ExqliteTest.Schema2,
        references: :x,
        foreign_key: :z
      )

      has_one(:permalink, Ecto.Adapters.ExqliteTest.Schema3,
        references: :y,
        foreign_key: :id
      )
    end
  end

  defmodule Schema2 do
    use Ecto.Schema

    schema "schema2" do
      belongs_to(:post, Ecto.Adapters.ExqliteTest.Schema,
        references: :x,
        foreign_key: :z
      )
    end
  end

  defmodule Schema3 do
    use Ecto.Schema

    schema "schema3" do
      field(:binary, :binary)
    end
  end

  defp plan(query, operation \\ :all) do
    {query, _params} =
      Ecto.Adapter.Queryable.plan_query(operation, Ecto.Adapters.Exqlite, query)

    query
  end

  ##
  ## Helpers
  ##

  defp all(query), do: query |> Connection.all() |> IO.iodata_to_binary()
  defp update_all(query), do: query |> Connection.update_all() |> IO.iodata_to_binary()
  defp delete_all(query), do: query |> Connection.delete_all() |> IO.iodata_to_binary()

  defp execute_ddl(query) do
    query
    |> Connection.execute_ddl()
    |> Enum.map(&IO.iodata_to_binary/1)
  end

  defp insert(prefx, table, header, rows, on_conflict, returning) do
    Connection.insert(prefx, table, header, rows, on_conflict, returning, [])
    |> IO.iodata_to_binary()
  end

  defp update(prefx, table, fields, filter, returning) do
    Connection.update(prefx, table, fields, filter, returning)
    |> IO.iodata_to_binary()
  end

  defp delete(prefx, table, filter, returning) do
    Connection.delete(prefx, table, filter, returning)
    |> IO.iodata_to_binary()
  end

  defp remove_newlines(string) do
    string
    |> String.trim()
    |> String.replace("\n", " ")
  end

  ##
  ## Tests
  ##

  describe ".all/1" do
    test "thing" do
      Schema
      |> Ecto.Query.select([r], r.x)
      |> plan()
      |> Connection.all()

      query = Schema |> select([r], r.x) |> plan()
      assert all(query) == ~s{SELECT s0.x FROM schema AS s0}
    end
  end

  describe ".create_alias/1" do
    test "returns first character" do
      assert ?p == Connection.create_alias("post")
    end

    test "returns ?t when the first value is not a-z A-Z" do
      assert ?t == Connection.create_alias("0post")
    end
  end

  describe ".create_name/3" do
    test "for a fragment" do
      assert Connection.create_name({{:fragment, nil, nil}}, 0, []) ==
               {nil, [?f | "0"], nil}

      assert Connection.create_name({{}, {:fragment, nil, nil}}, 1, []) ==
               {nil, [?f | "1"], nil}

      assert Connection.create_name({{}, {}, {:fragment, nil, nil}}, 2, []) ==
               {nil, [?f | "2"], nil}
    end

    test "for a table" do
      assert Connection.create_name({{"table_name", "schema_name", nil}}, 0, []) ==
               {["table_name"], [?t | "0"], "schema_name"}

      assert Connection.create_name({{}, {"table_name", "schema_name", nil}}, 1, []) ==
               {["table_name"], [?t | "1"], "schema_name"}

      assert Connection.create_name({{}, {}, {"table_name", "schema_name", nil}}, 2, []) ==
               {["table_name"], [?t | "2"], "schema_name"}
    end
  end

  describe ".create_names/1" do
    test "creates names with a schema" do
      query = select(Schema, [r], r.x) |> plan()
      assert Connection.create_names(query) == {{["schema"], [?s | "0"], Schema}, []}
    end

    test "creates names without a schema" do
      query = select("posts", [r], r.x) |> plan()
      assert Connection.create_names(query) == {{["posts"], [?p | "0"], nil}, []}
    end

    test "creates names with a fragment" do
      query = select("posts", [r], fragment("?", r)) |> plan()
      assert Connection.create_names(query) == {{["posts"], [?p | "0"], nil}, []}
    end

    test "creates names that have a leading number" do
      query = select("0posts", [:x]) |> plan()
      assert Connection.create_names(query) == {{["0posts"], [?t | "0"], nil}, []}
    end

    test "creates names without a schema and a subquery" do
      query =
        subquery("posts" |> select([r], %{x: r.x, y: r.y}))
        |> select([r], r.x)
        |> plan()

      assert Connection.create_names(query) == {{nil, [?s | "0"], nil}, []}
    end

    test "creates names with deeper selects" do
      query =
        subquery("posts" |> select([r], %{x: r.x, z: r.y})) |> select([r], r) |> plan()

      assert Connection.create_names(query) == {{nil, [?s | "0"], nil}, []}
    end

    test "creates names with a subquery of another subquery" do
      query =
        subquery(subquery("posts" |> select([r], %{x: r.x, z: r.y})) |> select([r], r))
        |> select([r], r)
        |> plan()

      assert Connection.create_names(query) == {{nil, [?s | "0"], nil}, []}
    end
  end
end
