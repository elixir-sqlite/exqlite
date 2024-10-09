sql = """
with recursive cte(i) as (
  values(0)
  union all
  select i + 1 from cte where i < ?
)
select 'hello' || i from cte
"""

alias Exqlite.Sqlite3

Benchee.run(
  %{"fetch_all" => fn %{conn: conn, stmt: stmt} -> Sqlite3.fetch_all(conn, stmt) end},
  inputs: %{
    "10 rows" => 10,
    "100 rows" => 100,
    "1000 rows" => 1000,
    "10000 rows" => 10000
  },
  before_scenario: fn rows ->
    {:ok, conn} = Sqlite3.open(":memory:", [:readonly, :nomutex])
    {:ok, stmt} = Sqlite3.prepare(conn, sql)
    Sqlite3.bind(conn, stmt, [rows])
    %{conn: conn, stmt: stmt}
  end,
  after_scenario: fn %{conn: conn, stmt: stmt} ->
    Sqlite3.release(conn, stmt)
    Sqlite3.close(conn)
  end
)
