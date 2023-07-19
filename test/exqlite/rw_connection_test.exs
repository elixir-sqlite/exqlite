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
      assert :sys.get_state(conn).lock == :none

      task =
        Task.async(fn ->
          RWConnection.query(conn, burn(1_000_000))
        end)

      :timer.sleep(100)
      assert {writer_ref, statement_ref} = :sys.get_state(conn).lock
      assert is_reference(writer_ref)
      assert is_reference(statement_ref)

      Task.await(task)
      assert :sys.get_state(conn).lock == :none
    end

    test "queues commands when locked", %{conn: conn} do
      Task.async(fn -> RWConnection.query(conn, burn(1_000_000)) end)
      Task.async(fn -> RWConnection.query(conn, burn(1_000_000)) end)
      task = Task.async(fn -> RWConnection.query(conn, burn(1_000_000)) end)

      :timer.sleep(100)
      assert :queue.len(:sys.get_state(conn).queue) == 2

      Task.await(task)
      assert :queue.len(:sys.get_state(conn).queue) == 0
      assert :sys.get_state(conn).lock == :none
    end

    test "drains reads before locking", %{conn: conn} do
      Task.async(fn -> RWConnection.read_query(conn, burn(1_000_000)) end)
      Task.async(fn -> RWConnection.read_query(conn, burn(1_000_000)) end)
      task = Task.async(fn -> RWConnection.query(conn, burn(1_000_000)) end)

      :timer.sleep(100)
      assert :sys.get_state(conn).lock == :drain
      assert map_size(:sys.get_state(conn).reads) == 2
      assert :queue.len(:sys.get_state(conn).queue) == 1

      Task.await(task)

      assert :sys.get_state(conn).lock == :none
      assert map_size(:sys.get_state(conn).reads) == 0
      assert :queue.len(:sys.get_state(conn).queue) == 0
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
      assert :sys.get_state(conn).lock == :none

      task = Task.async(fn -> RWConnection.read_query(conn, burn(1_000_000)) end)

      :timer.sleep(100)
      assert :sys.get_state(conn).lock == :none
      assert map_size(:sys.get_state(conn).reads) == 1

      Task.await(task)
      assert :sys.get_state(conn).lock == :none
      assert map_size(:sys.get_state(conn).reads) == 0
    end

    test "concurrent", %{conn: conn} do
      test = self()

      Task.async(fn ->
        RWConnection.read_query(conn, burn(1_000_000))
        send(test, {:t1, System.monotonic_time(:millisecond)})
      end)

      Task.async(fn ->
        RWConnection.read_query(conn, burn(1_000_000))
        send(test, {:t2, System.monotonic_time(:millisecond)})
      end)

      assert_receive {:t1, t1_over}, :timer.seconds(5)
      assert_receive {:t2, t2_over}, :timer.seconds(5)
      assert_in_delta t1_over, t2_over, 500
    end

    test "queues reads when connection is locked", %{conn: conn} do
      Task.async(fn -> RWConnection.query(conn, burn(1_000_000)) end)
      task = Task.async(fn -> RWConnection.read_query(conn, burn(1_000_000)) end)

      :timer.sleep(100)
      assert {_, _} = _refs = :sys.get_state(conn).lock
      assert map_size(:sys.get_state(conn).reads) == 0
      assert :queue.len(:sys.get_state(conn).queue) == 1

      Task.await(task)
      assert :sys.get_state(conn).lock == :none
      assert map_size(:sys.get_state(conn).reads) == 0
      assert :queue.len(:sys.get_state(conn).queue) == 0
    end

    test "queues reads when draining", %{conn: conn} do
      Task.async(fn -> RWConnection.read_query(conn, burn(1_000_000)) end)
      Task.async(fn -> RWConnection.query(conn, burn(1_000_000)) end)
      task = Task.async(fn -> RWConnection.read_query(conn, burn(1_000_000)) end)

      :timer.sleep(100)
      assert :sys.get_state(conn).lock == :drain
      assert map_size(:sys.get_state(conn).reads) == 1
      assert :queue.len(:sys.get_state(conn).queue) == 2

      Task.await(task)
      assert :sys.get_state(conn).lock == :none
      assert map_size(:sys.get_state(conn).reads) == 0
      assert :queue.len(:sys.get_state(conn).queue) == 0
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
end
