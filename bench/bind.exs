{:ok, db} = Exqlite.open(":memory:", [:readwrite, :nomutex])
{:ok, stmt} = Exqlite.prepare(db, "select ? + 1")

Benchee.run(%{
  "bind_all" => fn -> Exqlite.bind_all(db, stmt, [1]) end,
  "dirty_cpu_bind_all" => fn -> Exqlite.dirty_cpu_bind_all(db, stmt, [1]) end
})
