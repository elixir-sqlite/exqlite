tmp_dir = Path.expand(Path.join("./tmp", "bench/step"))
File.mkdir_p!(tmp_dir)

path = Path.join(tmp_dir, "db.sqlite")
if File.exists?(path), do: File.rm!(path)

IO.puts("Creating DB at #{path} ...")
{:ok, db} = Exqlite.open(path, [:readwrite, :nomutex, :create])

IO.puts("Inserting 1000 rows ...")
:ok = Exqlite.execute(db, "create table test(stuff text)")
{:ok, insert} = Exqlite.prepare(db, "insert into test(stuff) values(?)")
:ok = Exqlite.insert_all(db, insert, Enum.map(1..1000, fn i -> ["name-#{i}"] end))
:ok = Exqlite.finalize(insert)

select = fn limit ->
  {:ok, select} = Exqlite.prepare(db, "select * from test limit #{limit}")
  select
end

defmodule Bench do
  def step_all(db, stmt) do
    case Exqlite.step(db, stmt) do
      {:row, _} -> step_all(db, stmt)
      :done -> :ok
    end
  end

  def dirty_io_step_all(db, stmt) do
    case Exqlite.dirty_io_step(db, stmt) do
      {:row, _} -> dirty_io_step_all(db, stmt)
      :done -> :ok
    end
  end

  def multi_step_all(db, stmt, steps) do
    case Exqlite.multi_step(db, stmt, steps) do
      {:rows, _} -> multi_step_all(db, stmt, steps)
      {:done, _} -> :ok
    end
  end
end

IO.puts("Running benchmarks ...\n")

Benchee.run(
  %{
    "step" => fn stmt -> Bench.step_all(db, stmt) end,
    "dirty_io_step" => fn stmt -> Bench.dirty_io_step_all(db, stmt) end,
    "multi_step(100)" => fn stmt -> Bench.multi_step_all(db, stmt, _steps = 100) end
  },
  inputs: %{
    "10 rows" => select.(10),
    "100 rows" => select.(100),
    "500 rows" => select.(500)
  },
  memory_time: 2
)
