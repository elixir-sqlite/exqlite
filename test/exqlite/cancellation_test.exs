defmodule Exqlite.CancellationTest do
  @moduledoc """
  Tests for query cancellation and deadlock prevention (issue #192).

  Validates that queries can be cancelled in flight and that disconnect
  properly interrupts stuck queries to prevent pool deadlocks.
  """

  use ExUnit.Case

  alias Exqlite.Sqlite3

  @moduletag :slow_test

  @long_running_select """
  WITH RECURSIVE r(i) AS (
    VALUES(0) UNION ALL SELECT i FROM r LIMIT 1000000000
  ) SELECT i FROM r WHERE i = 1;
  """

  @long_running_insert """
  WITH RECURSIVE r(i) AS (
    VALUES(0) UNION ALL SELECT i+1 FROM r LIMIT 1000000000
  ) INSERT INTO t SELECT i FROM r;
  """

  defp with_db(fun), do: with_db(":memory:", fun)

  defp with_db(path, fun) do
    {:ok, db} = Sqlite3.open(path)

    try do
      fun.(db)
    after
      Sqlite3.close(db)
    end
  end

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

  defp interrupt_long_query(db, query, opts \\ []) do
    delay = Keyword.get(opts, :delay, 200)
    parent = self()

    spawn(fn ->
      result =
        case Keyword.get(opts, :mode, :multi_step) do
          :multi_step ->
            {:ok, stmt} = Sqlite3.prepare(db, query)
            Sqlite3.multi_step(db, stmt, 50)

          :execute ->
            Sqlite3.execute(db, query)
        end

      send(parent, {:query_result, result})
    end)

    Process.sleep(delay)
    :ok = Sqlite3.interrupt(db)

    receive do
      {:query_result, result} -> result
    after
      5_000 -> flunk("query did not return within 5s after interrupt")
    end
  end

  # -- Interrupt basics -------------------------------------------------------

  describe "interrupt" do
    test "aborts a long-running SELECT via multi_step" do
      with_db(fn db ->
        assert {:error, _} = interrupt_long_query(db, @long_running_select)
      end)
    end

    test "aborts a long-running SELECT via execute" do
      with_db(fn db ->
        assert {:error, _} =
                 interrupt_long_query(db, @long_running_select, mode: :execute)
      end)
    end

    test "aborts a long-running INSERT" do
      with_db(fn db ->
        :ok = Sqlite3.execute(db, "CREATE TABLE t (i INTEGER)")

        assert {:error, _} =
                 interrupt_long_query(db, @long_running_insert, mode: :execute)
      end)
    end

    test "interrupt latency is under 2 seconds" do
      with_db(fn db ->
        {:ok, stmt} = Sqlite3.prepare(db, @long_running_select)
        parent = self()

        spawn(fn ->
          result = Sqlite3.multi_step(db, stmt, 50)
          send(parent, {:query_result, result})
        end)

        Process.sleep(200)
        t0 = System.monotonic_time(:millisecond)
        :ok = Sqlite3.interrupt(db)
        assert_receive {:query_result, {:error, _}}, 5_000
        assert System.monotonic_time(:millisecond) - t0 < 2_000
      end)
    end

    test "has no effect when called before a query starts" do
      with_db(fn db ->
        :ok = Sqlite3.execute(db, "CREATE TABLE t (x INTEGER)")
        :ok = Sqlite3.execute(db, "INSERT INTO t VALUES(42)")

        :ok = Sqlite3.interrupt(db)

        {:ok, stmt} = Sqlite3.prepare(db, "SELECT x FROM t")
        assert {:done, [[42]]} = Sqlite3.multi_step(db, stmt, 50)
      end)
    end
  end

  # -- Connection state after interrupt ----------------------------------------

  describe "connection after interrupt" do
    test "is still usable for new queries" do
      with_db(fn db ->
        :ok = Sqlite3.execute(db, "CREATE TABLE t (x INTEGER)")
        :ok = Sqlite3.execute(db, "INSERT INTO t VALUES(42)")

        {:error, _} = interrupt_long_query(db, @long_running_select)

        {:ok, stmt} = Sqlite3.prepare(db, "SELECT x FROM t")
        assert {:done, [[42]]} = Sqlite3.multi_step(db, stmt, 50)
      end)
    end

    test "survives 10 consecutive interrupt cycles" do
      with_db(fn db ->
        :ok = Sqlite3.execute(db, "CREATE TABLE t (x INTEGER)")
        :ok = Sqlite3.execute(db, "INSERT INTO t VALUES(1)")

        for _cycle <- 1..10 do
          {:error, _} = interrupt_long_query(db, @long_running_select, delay: 50)
        end

        {:ok, stmt} = Sqlite3.prepare(db, "SELECT x FROM t")
        assert {:done, [[1]]} = Sqlite3.multi_step(db, stmt, 50)
      end)
    end

    test "interrupted write inside BEGIN leaves transaction rollback-able" do
      with_db(fn db ->
        :ok = Sqlite3.execute(db, "CREATE TABLE t (i INTEGER)")
        :ok = Sqlite3.execute(db, "INSERT INTO t VALUES(1)")
        :ok = Sqlite3.execute(db, "BEGIN IMMEDIATE")

        {:error, _} = interrupt_long_query(db, @long_running_insert, mode: :execute)

        {:ok, status} = Sqlite3.transaction_status(db)

        case status do
          :transaction -> :ok = Sqlite3.execute(db, "ROLLBACK")
          :idle -> :ok
        end

        {:ok, stmt} = Sqlite3.prepare(db, "SELECT count(*) FROM t")
        assert {:done, [[1]]} = Sqlite3.multi_step(db, stmt, 50)
      end)
    end
  end

  # -- Interrupt + close race (PR #342 validation) ----------------------------

  describe "interrupt + close race safety" do
    test "100 cycles of query/interrupt/close/reopen" do
      for cycle <- 1..100 do
        {:ok, db} = Sqlite3.open(":memory:")
        parent = self()

        spawn(fn ->
          {:ok, stmt} = Sqlite3.prepare(db, @long_running_select)
          result = Sqlite3.multi_step(db, stmt, 50)
          send(parent, {:done, result})
        end)

        Process.sleep(10)
        :ok = Sqlite3.interrupt(db)

        receive do
          {:done, _} -> :ok
        after
          5_000 -> flunk("cycle #{cycle}: query did not return after interrupt")
        end

        :ok = Sqlite3.close(db)
      end
    end
  end

  # -- Busy handler vs interrupt -----------------------------------------------

  describe "interrupt vs busy handler" do
    test "interrupt does NOT break through busy handler sleep" do
      with_file_db(fn path ->
        {:ok, db1} = Sqlite3.open(path)
        {:ok, db2} = Sqlite3.open(path)

        :ok = Sqlite3.execute(db1, "PRAGMA journal_mode=WAL")
        :ok = Sqlite3.execute(db1, "CREATE TABLE t (i INTEGER)")
        :ok = Sqlite3.execute(db1, "INSERT INTO t VALUES(1)")
        :ok = Sqlite3.set_busy_timeout(db2, 30_000)

        # db1 holds an exclusive write lock
        :ok = Sqlite3.execute(db1, "BEGIN IMMEDIATE")
        :ok = Sqlite3.execute(db1, "INSERT INTO t VALUES(2)")

        parent = self()

        # db2 tries to write — enters busy handler sleep loop
        spawn(fn ->
          result = Sqlite3.execute(db2, "BEGIN IMMEDIATE")
          send(parent, {:db2_result, result})
        end)

        Process.sleep(500)
        :ok = Sqlite3.interrupt(db2)

        # db2 should NOT return within 5s — interrupt doesn't affect busy handler
        got_response =
          receive do
            {:db2_result, _} -> true
          after
            5_000 -> false
          end

        # Release the lock so db2 can finish
        Sqlite3.execute(db1, "ROLLBACK")

        unless got_response do
          receive do
            {:db2_result, _} -> :ok
          after
            35_000 -> :ok
          end
        end

        Sqlite3.close(db1)
        Sqlite3.close(db2)

        refute got_response,
               "interrupt broke through busy handler — expected it to stay blocked"
      end)
    end
  end

  # -- Concurrent reads on single connection -----------------------------------

  describe "concurrent reads on single connection" do
    test "20 concurrent readers all get correct results" do
      with_db(fn db ->
        :ok = Sqlite3.execute(db, "CREATE TABLE t (id INTEGER PRIMARY KEY)")

        for i <- 1..100 do
          :ok = Sqlite3.execute(db, "INSERT INTO t VALUES(#{i})")
        end

        parent = self()

        for idx <- 1..20 do
          spawn(fn ->
            {:ok, stmt} = Sqlite3.prepare(db, "SELECT count(*) FROM t")
            result = Sqlite3.multi_step(db, stmt, 50)
            send(parent, {:reader, idx, result})
          end)
        end

        for _ <- 1..20 do
          assert_receive {:reader, _idx, {:done, [[100]]}}, 10_000
        end
      end)
    end
  end

  # -- Single-connection isolation ---------------------------------------------

  describe "single-connection isolation" do
    test "reads see own uncommitted writes" do
      with_db(fn db ->
        :ok = Sqlite3.execute(db, "CREATE TABLE t (x INTEGER)")
        :ok = Sqlite3.execute(db, "INSERT INTO t VALUES(1)")

        :ok = Sqlite3.execute(db, "BEGIN")
        :ok = Sqlite3.execute(db, "INSERT INTO t VALUES(2)")

        {:ok, stmt} = Sqlite3.prepare(db, "SELECT count(*) FROM t")
        {:done, [[count]]} = Sqlite3.multi_step(db, stmt, 50)

        assert count == 2
        :ok = Sqlite3.execute(db, "ROLLBACK")
      end)
    end
  end

  # -- Implicit transaction staleness (two connections, WAL) -------------------

  describe "implicit transaction staleness" do
    test "completed statement allows reader to see new data" do
      with_file_db(fn path ->
        {:ok, writer} = Sqlite3.open(path)
        {:ok, reader} = Sqlite3.open(path)

        :ok = Sqlite3.execute(writer, "PRAGMA journal_mode=WAL")
        :ok = Sqlite3.execute(writer, "CREATE TABLE t (i INTEGER)")
        :ok = Sqlite3.execute(writer, "INSERT INTO t VALUES(1)")

        {:ok, stmt1} = Sqlite3.prepare(reader, "SELECT * FROM t")
        {:done, [[1]]} = Sqlite3.multi_step(reader, stmt1, 50)

        :ok = Sqlite3.execute(writer, "INSERT INTO t VALUES(2)")

        {:ok, stmt2} = Sqlite3.prepare(reader, "SELECT count(*) FROM t")
        {:done, [[count]]} = Sqlite3.multi_step(reader, stmt2, 50)
        assert count == 2

        Sqlite3.close(writer)
        Sqlite3.close(reader)
      end)
    end

    test "in-progress statement keeps reader on stale snapshot" do
      with_file_db(fn path ->
        {:ok, writer} = Sqlite3.open(path)
        {:ok, reader} = Sqlite3.open(path)

        :ok = Sqlite3.execute(writer, "PRAGMA journal_mode=WAL")
        :ok = Sqlite3.execute(writer, "CREATE TABLE t (i INTEGER)")
        for i <- 1..10, do: Sqlite3.execute(writer, "INSERT INTO t VALUES(#{i})")

        # Step partially — implicit read tx still open
        {:ok, stmt1} = Sqlite3.prepare(reader, "SELECT * FROM t")
        {:rows, _partial} = Sqlite3.multi_step(reader, stmt1, 3)

        :ok = Sqlite3.execute(writer, "INSERT INTO t VALUES(99)")

        {:ok, stmt2} = Sqlite3.prepare(reader, "SELECT count(*) FROM t")
        {:done, [[count_stale]]} = Sqlite3.multi_step(reader, stmt2, 50)
        assert count_stale == 10

        # Finish stmt1
        _rest = Sqlite3.multi_step(reader, stmt1, 50)

        {:ok, stmt3} = Sqlite3.prepare(reader, "SELECT count(*) FROM t")
        {:done, [[count_fresh]]} = Sqlite3.multi_step(reader, stmt3, 50)
        assert count_fresh == 11

        Sqlite3.close(writer)
        Sqlite3.close(reader)
      end)
    end
  end

  # -- Close blocks on mutex ---------------------------------------------------

  describe "close vs running query" do
    test "close blocks until interrupt releases the mutex" do
      {:ok, db} = Sqlite3.open(":memory:")
      {:ok, stmt} = Sqlite3.prepare(db, @long_running_select)
      parent = self()

      spawn(fn ->
        result = Sqlite3.multi_step(db, stmt, 50)
        send(parent, {:query_done, result})
      end)

      Process.sleep(200)

      spawn(fn ->
        result = Sqlite3.close(db)
        send(parent, {:close_done, result})
      end)

      # Close should NOT return yet — it's blocked on the mutex
      refute_receive {:close_done, _}, 500

      :ok = Sqlite3.interrupt(db)

      assert_receive {:query_done, {:error, _}}, 5_000
      assert_receive {:close_done, :ok}, 5_000
    end
  end

  # -- WAL concurrent access patterns -----------------------------------------

  describe "WAL mode" do
    test "concurrent reads from two connections succeed" do
      with_file_db(fn path ->
        {:ok, db1} = Sqlite3.open(path)
        {:ok, db2} = Sqlite3.open(path)

        :ok = Sqlite3.execute(db1, "PRAGMA journal_mode=WAL")
        :ok = Sqlite3.execute(db1, "CREATE TABLE t (i INTEGER)")
        for i <- 1..100, do: Sqlite3.execute(db1, "INSERT INTO t VALUES(#{i})")

        {:ok, s1} = Sqlite3.prepare(db1, "SELECT count(*) FROM t")
        {:ok, s2} = Sqlite3.prepare(db2, "SELECT count(*) FROM t")

        assert {:done, [[100]]} = Sqlite3.multi_step(db1, s1, 50)
        assert {:done, [[100]]} = Sqlite3.multi_step(db2, s2, 50)

        Sqlite3.close(db1)
        Sqlite3.close(db2)
      end)
    end

    test "second writer gets SQLITE_BUSY with busy_timeout=0" do
      with_file_db(fn path ->
        {:ok, db1} = Sqlite3.open(path)
        {:ok, db2} = Sqlite3.open(path)

        :ok = Sqlite3.execute(db1, "PRAGMA journal_mode=WAL")
        :ok = Sqlite3.execute(db2, "PRAGMA journal_mode=WAL")
        :ok = Sqlite3.set_busy_timeout(db1, 0)
        :ok = Sqlite3.set_busy_timeout(db2, 0)
        :ok = Sqlite3.execute(db1, "CREATE TABLE t (i INTEGER)")

        :ok = Sqlite3.execute(db1, "BEGIN IMMEDIATE")
        :ok = Sqlite3.execute(db1, "INSERT INTO t VALUES(1)")

        assert {:error, _} = Sqlite3.execute(db2, "BEGIN IMMEDIATE")

        Sqlite3.execute(db1, "ROLLBACK")
        Sqlite3.close(db1)
        Sqlite3.close(db2)
      end)
    end

    test "deferred read tx conflicts with concurrent write" do
      with_file_db(fn path ->
        {:ok, c1} = Sqlite3.open(path)
        {:ok, c2} = Sqlite3.open(path)

        :ok = Sqlite3.execute(c1, "PRAGMA journal_mode=WAL")
        :ok = Sqlite3.set_busy_timeout(c1, 0)
        :ok = Sqlite3.set_busy_timeout(c2, 0)
        :ok = Sqlite3.execute(c1, "CREATE TABLE t (i INTEGER)")
        :ok = Sqlite3.execute(c1, "INSERT INTO t VALUES(1)")

        :ok = Sqlite3.execute(c1, "BEGIN")
        {:ok, stmt} = Sqlite3.prepare(c1, "SELECT * FROM t")
        {:done, [[1]]} = Sqlite3.multi_step(c1, stmt, 50)

        :ok = Sqlite3.execute(c2, "DELETE FROM t WHERE i = 1")

        assert {:error, _} = Sqlite3.execute(c1, "INSERT INTO t VALUES(2)")

        Sqlite3.execute(c1, "ROLLBACK")
        Sqlite3.close(c1)
        Sqlite3.close(c2)
      end)
    end
  end

  # -- DBConnection pool recovery after timeout --------------------------------

  describe "DBConnection timeout recovery" do
    @tag timeout: 30_000
    test "pool recovers after a long query is interrupted on disconnect" do
      with_file_db(fn path ->
        {:ok, conn} =
          Exqlite.start_link(
            database: path,
            journal_mode: :wal,
            timeout: 1_000,
            busy_timeout: 0,
            pool_size: 1
          )

        Exqlite.query!(conn, "CREATE TABLE t (i INTEGER)", [])
        Exqlite.query!(conn, "INSERT INTO t VALUES(1)", [])

        # The long query should be interrupted when DBConnection's timeout
        # triggers a disconnect, which now calls Sqlite3.cancel/1.
        result =
          try do
            Exqlite.query(conn, @long_running_select, [], timeout: 1_000)
          rescue
            e -> {:exception, e}
          catch
            :exit, reason -> {:exit, reason}
          end

        assert match?({:exit, _}, result) or match?({:error, _}, result)

        # Pool should recover — next query should work
        assert {:ok, %Exqlite.Result{rows: [[1]]}} =
                 Exqlite.query(conn, "SELECT count(*) FROM t", [], timeout: 5_000)

        GenServer.stop(conn, :normal, 5_000)
      end)
    end

    @tag timeout: 30_000
    test "pool recovers when query is stuck in busy handler" do
      with_file_db(fn path ->
        # Open a raw connection that will hold an exclusive lock
        {:ok, blocker} = Sqlite3.open(path)
        :ok = Sqlite3.execute(blocker, "PRAGMA journal_mode=WAL")
        :ok = Sqlite3.execute(blocker, "CREATE TABLE t (i INTEGER)")
        :ok = Sqlite3.execute(blocker, "INSERT INTO t VALUES(1)")

        # Pool connection gets a long busy_timeout so it enters the sleep loop
        {:ok, conn} =
          Exqlite.start_link(
            database: path,
            journal_mode: :wal,
            timeout: 2_000,
            busy_timeout: 60_000,
            pool_size: 1
          )

        # Blocker grabs exclusive write lock
        :ok = Sqlite3.execute(blocker, "BEGIN IMMEDIATE")
        :ok = Sqlite3.execute(blocker, "INSERT INTO t VALUES(2)")

        parent = self()

        # Pool tries to write — enters busy handler sleep loop waiting for lock
        spawn(fn ->
          result =
            try do
              Exqlite.query(conn, "INSERT INTO t VALUES(3)", [], timeout: 2_000)
            rescue
              e -> {:exception, e}
            catch
              :exit, reason -> {:exit, reason}
            end

          send(parent, {:pool_result, result})
        end)

        # The pool query should return within 15s because disconnect calls
        # cancel(), which breaks through the busy handler sleep loop
        # (the fix for issue #192).
        pool_returned =
          receive do
            {:pool_result, _result} -> true
          after
            15_000 -> false
          end

        # Release the lock so everything can unwind
        Sqlite3.execute(blocker, "ROLLBACK")

        unless pool_returned do
          receive do
            {:pool_result, _} -> :ok
          after
            65_000 -> :ok
          end
        end

        Sqlite3.close(blocker)

        assert pool_returned,
               "Pool is stuck in busy handler — disconnect needs a custom busy handler to fix this"
      end)
    end
  end

  # -- Watchdog pattern --------------------------------------------------------

  describe "watchdog pattern" do
    test "auto-interrupts a query after a timeout" do
      with_db(fn db ->
        {:ok, stmt} = Sqlite3.prepare(db, @long_running_select)
        timeout_ms = 500

        watchdog =
          spawn(fn ->
            receive do
              :cancel -> :ok
            after
              timeout_ms -> Sqlite3.interrupt(db)
            end
          end)

        {elapsed_us, result} =
          :timer.tc(fn -> Sqlite3.multi_step(db, stmt, 50) end)

        send(watchdog, :cancel)

        assert {:error, _} = result
        assert div(elapsed_us, 1000) < timeout_ms + 2_000
      end)
    end

    test "cancelling the watchdog lets the query complete normally" do
      with_db(fn db ->
        :ok = Sqlite3.execute(db, "CREATE TABLE t (x INTEGER)")
        :ok = Sqlite3.execute(db, "INSERT INTO t VALUES(1)")

        {:ok, stmt} = Sqlite3.prepare(db, "SELECT x FROM t")

        watchdog =
          spawn(fn ->
            receive do
              :cancel -> :ok
            after
              5_000 -> Sqlite3.interrupt(db)
            end
          end)

        result = Sqlite3.multi_step(db, stmt, 50)
        send(watchdog, :cancel)

        assert {:done, [[1]]} = result
      end)
    end
  end
end
