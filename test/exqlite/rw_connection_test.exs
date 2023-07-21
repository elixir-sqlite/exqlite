defmodule Exqlite.RWConnectionTest do
  use ExUnit.Case
  alias Exqlite.{RWConnection, Result}

  setup do
    path = Temp.path!()
    on_exit(fn -> File.rm!(path) end)
    {:ok, path: path}
  end

  describe "start_link" do
    test "starts connection process", %{path: path} do
      assert {:ok, conn} = RWConnection.start_link(database: path)

      # write db check
      assert {:ok, %Result{columns: ["journal_mode"], rows: [["wal"]]}} =
               RWConnection.query(conn, "pragma journal_mode")

      assert {:ok, %Exqlite.Result{columns: ["foreign_keys"], rows: [[1]]}} =
               RWConnection.query(conn, "pragma foreign_keys")

      # read db check
      assert {:ok, %Result{columns: ["journal_mode"], rows: [["wal"]]}} =
               RWConnection.read_query(conn, "pragma journal_mode")

      assert {:ok, %Exqlite.Result{columns: ["foreign_keys"], rows: [[1]]}} =
               RWConnection.read_query(conn, "pragma foreign_keys")
    end
  end

  describe "query" do
    setup :conn

    test "handles incorrect queries", %{conn: conn} do
      assert {:error, %Exqlite.Error{message: "incomplete input"}} =
               RWConnection.query(conn, "select")

      assert {:error, %Exqlite.Error{message: "arguments_wrong_length"}} =
               RWConnection.query(conn, "select ? + ?", [1])

      assert {:error, %Exqlite.Error{message: "arguments_wrong_length"}} =
               RWConnection.query(conn, "select ? + ?", [1, 2, 3])

      assert {:error, %Exqlite.Error{message: ~s[near "eh": syntax error]}} =
               RWConnection.query(conn, "eh")
    end

    test "locks connection", %{conn: conn} do
      assert state(conn, :lock) == :none

      write = Task.async(fn -> RWConnection.query(conn, burn(1_000_000)) end)

      :timer.sleep(100)
      assert {writer_ref, statement_ref} = state(conn, :lock)
      assert is_reference(writer_ref)
      assert is_reference(statement_ref)

      Task.await(write)
      assert state(conn, :lock) == :none
    end

    test "queues commands when locked", %{conn: conn} do
      _1 = Task.async(fn -> RWConnection.query(conn, burn(1_000_000)) end)
      _2 = Task.async(fn -> RWConnection.query(conn, "select 1") end)
      w3 = Task.async(fn -> RWConnection.query(conn, "select 1") end)

      :timer.sleep(100)
      assert :queue.len(state(conn, :write_queue)) == 2

      Task.await(w3)
      assert :queue.len(state(conn, :write_queue)) == 0
      assert :sys.get_state(conn).lock == :none
    end

    test "drains reads after locking", %{conn: conn} do
      r1 = Task.async(fn -> RWConnection.read_query(conn, burn(1_000_000)) end)
      r2 = Task.async(fn -> RWConnection.read_query(conn, burn(1_000_000)) end)

      w3 =
        Task.async(fn ->
          RWConnection.query(conn, "select 1")
          RWConnection.read_query(conn, burn(1_000_000))
        end)

      :timer.sleep(10)
      assert map_size(state(conn, :reads)) == 2
      assert :queue.len(state(conn, :read_queue)) == 1
      refute state(conn, :readable)

      Task.await_many([r1, r2])
      assert map_size(state(conn, :reads)) == 1
      assert :queue.len(state(conn, :read_queue)) == 0
      assert state(conn, :readable)

      Task.await(w3)
      assert map_size(state(conn, :reads)) == 0
    end
  end

  describe "read_query" do
    setup :conn

    test "handles incorrect queries", %{conn: conn} do
      assert {:error, %Exqlite.Error{message: "incomplete input"}} =
               RWConnection.read_query(conn, "select")

      assert {:error, %Exqlite.Error{message: "arguments_wrong_length"}} =
               RWConnection.read_query(conn, "select ? + ?", [1])

      assert {:error, %Exqlite.Error{message: "arguments_wrong_length"}} =
               RWConnection.read_query(conn, "select ? + ?", [1, 2, 3])

      assert {:error, %Exqlite.Error{message: ~s[near "eh": syntax error]}} =
               RWConnection.read_query(conn, "eh")
    end

    test "doesn't lock connection", %{conn: conn} do
      assert state(conn, :lock) == :none

      read = Task.async(fn -> RWConnection.read_query(conn, burn(1_000_000)) end)

      :timer.sleep(100)
      assert state(conn, :lock) == :none
      assert map_size(state(conn, :reads)) == 1

      Task.await(read)
      assert state(conn, :lock) == :none
      assert map_size(state(conn, :reads)) == 0
    end

    test "is concurrent", %{conn: conn} do
      test = self()

      Task.async(fn ->
        began = System.monotonic_time()
        RWConnection.read_query(conn, burn(1_000_000))
        send(test, {:t1, began, System.monotonic_time()})
      end)

      Task.async(fn ->
        began = System.monotonic_time()
        RWConnection.read_query(conn, burn(1_000_000))
        send(test, {:t2, began, System.monotonic_time()})
      end)

      assert_receive {:t1, t1_began, t1_over}, :timer.seconds(5)
      assert_receive {:t2, t2_began, t2_over}, :timer.seconds(5)

      assert t1_over > t2_began
      assert t2_over > t1_began
    end

    test "doesn't queue reads when connection is locked", %{conn: conn} do
      w1 = Task.async(fn -> RWConnection.query(conn, burn(1_000_000)) end)
      r2 = Task.async(fn -> RWConnection.read_query(conn, burn(1_000_000)) end)

      :timer.sleep(100)
      assert {_, _} = _refs = state(conn, :lock)
      assert map_size(state(conn, :reads)) == 1
      assert :queue.len(state(conn, :read_queue)) == 0

      Task.await(w1)
      assert state(conn, :lock) == :none

      Task.await(r2)
      assert map_size(state(conn, :reads)) == 0
    end

    test "queues reads when draining", %{conn: conn} do
      _1 = Task.async(fn -> RWConnection.read_query(conn, burn(1_000_000)) end)

      w2 =
        Task.async(fn ->
          RWConnection.query(conn, "select 1")
          RWConnection.read_query(conn, "select 1")
        end)

      :timer.sleep(50)
      refute state(conn, :readable)
      assert map_size(state(conn, :reads)) == 1
      assert :queue.len(state(conn, :read_queue)) == 1

      Task.await(w2)
      assert state(conn, :readable)
      assert state(conn, :lock) == :none
      assert map_size(state(conn, :reads)) == 0
      assert :queue.len(state(conn, :read_queue)) == 0
    end
  end

  defp burn(count) when is_integer(count) do
    """
    WITH RECURSIVE generate_series(value) AS (
      SELECT 1 UNION ALL SELECT value+1 FROM generate_series WHERE value < #{count}
    )
    SELECT COUNT(*) FROM (SELECT value FROM generate_series);
    """
  end

  defp conn(%{path: path}) do
    {:ok, conn} = RWConnection.start_link(database: path)
    {:ok, conn: conn}
  end

  defp state(conn, key) do
    Map.fetch!(:sys.get_state(conn), key)
  end
end
