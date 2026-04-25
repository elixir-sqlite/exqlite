defmodule Exqlite.SanitizerTest do
  use ExUnit.Case

  alias Exqlite.Sqlite3

  @moduletag :sanitizer

  defp with_file_db(fun) do
    path = Temp.path!()

    try do
      fun.(path)
    after
      File.rm(path)
      File.rm(path <> "-wal")
      File.rm(path <> "-shm")
    end
  end

  test "busy handler cancellation is sanitizer-clean" do
    with_file_db(fn path ->
      {:ok, db1} = Sqlite3.open(path)
      {:ok, db2} = Sqlite3.open(path)

      try do
        :ok = Sqlite3.execute(db1, "PRAGMA journal_mode=WAL")
        :ok = Sqlite3.execute(db1, "CREATE TABLE t (i INTEGER)")
        :ok = Sqlite3.execute(db1, "INSERT INTO t VALUES(1)")
        :ok = Sqlite3.set_busy_timeout(db2, 60_000)
        :ok = Sqlite3.set_progress_handler_steps(db2, -1)

        :ok = Sqlite3.execute(db1, "BEGIN IMMEDIATE")
        :ok = Sqlite3.execute(db1, "INSERT INTO t VALUES(2)")

        parent = self()

        writer =
          spawn(fn ->
            result = Sqlite3.execute(db2, "INSERT INTO t VALUES(3)")
            send(parent, {:writer_done, result})
          end)

        Process.sleep(100)

        canceller =
          Task.async(fn ->
            for _ <- 1..200 do
              Sqlite3.cancel(db2)
              Process.sleep(1)
            end
          end)

        assert_receive {:writer_done, {:error, _}}, 5_000
        Task.await(canceller, 5_000)
        refute Process.alive?(writer)
      after
        Sqlite3.execute(db1, "ROLLBACK")
        Sqlite3.close(db1)
        Sqlite3.close(db2)
      end
    end)
  end

  test "busy timeout updates during contention are sanitizer-clean" do
    with_file_db(fn path ->
      {:ok, db1} = Sqlite3.open(path)
      {:ok, db2} = Sqlite3.open(path)

      try do
        :ok = Sqlite3.execute(db1, "PRAGMA journal_mode=WAL")
        :ok = Sqlite3.execute(db1, "CREATE TABLE t (i INTEGER)")
        :ok = Sqlite3.execute(db1, "INSERT INTO t VALUES(1)")
        :ok = Sqlite3.set_busy_timeout(db2, 60_000)
        :ok = Sqlite3.set_progress_handler_steps(db2, -1)

        :ok = Sqlite3.execute(db1, "BEGIN IMMEDIATE")
        :ok = Sqlite3.execute(db1, "INSERT INTO t VALUES(2)")

        parent = self()

        writer =
          spawn(fn ->
            result = Sqlite3.execute(db2, "INSERT INTO t VALUES(3)")
            send(parent, {:writer_done, result})
          end)

        Process.sleep(100)

        updater =
          Task.async(fn ->
            for timeout_ms <- Stream.cycle([0, 1, 5, 25, 250, 5_000]) |> Enum.take(500) do
              result = Sqlite3.set_busy_timeout(db2, timeout_ms)

              if result not in [:ok, {:error, :connection_closed}],
                do: flunk("unexpected result")
            end
          end)

        Process.sleep(50)
        :ok = Sqlite3.cancel(db2)

        assert_receive {:writer_done, {:error, _}}, 5_000
        Task.await(updater, 5_000)
        refute Process.alive?(writer)
      after
        Sqlite3.execute(db1, "ROLLBACK")
        Sqlite3.close(db1)
        Sqlite3.close(db2)
      end
    end)
  end
end
