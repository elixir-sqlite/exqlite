{:ok, db} = Exqlite.open(":memory:", [:readwrite])
:ok = Exqlite.execute(db, "create table test (id integer primary key, name text)")
{:ok, stmt} = Exqlite.prepare(db, "insert into test(name) values(?)")

Benchee.run(
  %{
    "insert_all" =>
      {fn rows -> Exqlite.insert_all(db, stmt, rows) end,
       before_scenario: fn _input -> Exqlite.execute(db, "truncate test") end}
  },
  inputs: %{
    "3 rows" => Enum.map(1..3, fn i -> ["name-#{i}"] end),
    "30 rows" => Enum.map(1..30, fn i -> ["name-#{i}"] end),
    "90 rows" => Enum.map(1..90, fn i -> ["name-#{i}"] end),
    "300 rows" => Enum.map(1..300, fn i -> ["name-#{i}"] end),
    "1000 rows" => Enum.map(1..1000, fn i -> ["name-#{i}"] end)
  }
)
