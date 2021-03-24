defmodule Exqlite.Sqlite3 do
  @moduledoc """
  The interface to the NIF implementation.
  """

  #
  # TODO: If the database reference is closed, any prepared statements should be
  #       dereferenced as well. It is entirely possible that an application does
  #       not properly remove a stale reference.
  #
  #       Will need to add a test for this and think of possible solution.
  #

  # TODO: Need to figure out if we can just stream results where we use this
  #       module as a sink.

  alias Exqlite.Sqlite3NIF

  @type db() :: reference()
  @type statement() :: reference()
  @type reason() :: atom() | String.t()
  @type row() :: []

  @doc """
  Opens a new sqlite database at the Path provided.

  If `path` can be `":memory"` to keep the sqlite database in memory.
  """
  @spec open(String.t()) :: {:ok, db()} | {:error, reason()}
  def open(path), do: Sqlite3NIF.open(String.to_charlist(path))

  @spec close(nil) :: :ok
  def close(nil), do: :ok

  @doc """
  Closes the database and releases any underlying resources.
  """
  @spec close(db()) :: :ok | {:error, reason()}
  def close(conn), do: Sqlite3NIF.close(conn)

  @doc """
  Executes an sql script. Multiple stanzas can be passed at once.
  """
  @spec execute(db(), String.t()) :: :ok | {:error, reason()}
  def execute(conn, sql) do
    case Sqlite3NIF.execute(conn, String.to_charlist(sql)) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
      _ -> {:error, "unhandled error"}
    end
  end

  @doc """
  Get the number of changes recently.

  **Note**: If triggers are used, the count may be larger than expected.

  See: https://sqlite.org/c3ref/changes.html
  """
  @spec changes(db()) :: {:ok, integer()}
  def changes(conn), do: Sqlite3NIF.changes(conn)

  @spec prepare(db(), String.t()) :: {:ok, statement()} | {:error, reason()}
  def prepare(conn, sql) do
    Sqlite3NIF.prepare(conn, String.to_charlist(sql))
  end

  @spec bind(db(), statement(), nil) :: :ok | {:error, reason()}
  def bind(conn, statement, nil), do: bind(conn, statement, [])

  @spec bind(db(), statement(), []) :: :ok | {:error, reason()}
  def bind(conn, statement, args) do
    Sqlite3NIF.bind(conn, statement, Enum.map(args, &convert/1))
  end

  @spec columns(db(), statement()) :: {:ok, []} | {:error, reason()}
  def columns(conn, statement), do: Sqlite3NIF.columns(conn, statement)

  @spec step(db(), statement()) :: :done | :busy | {:row, []}
  def step(conn, statement), do: Sqlite3NIF.step(conn, statement)

  @spec multi_step(db(), statement()) :: :busy | {:rows, [row()]} | {:done, [row()]}
  def multi_step(conn, statement) do
    chunk_size = Application.get_env(:exqlite, :default_chunk_size, 50)
    multi_step(conn, statement, chunk_size)
  end

  @spec multi_step(db(), statement(), integer()) ::
          :busy | {:rows, [row()]} | {:done, [row()]}
  def multi_step(conn, statement, chunk_size) do
    case Sqlite3NIF.multi_step(conn, statement, chunk_size) do
      :busy ->
        {:error, "Database busy"}

      {:error, reason} ->
        {:error, reason}

      {:rows, rows} ->
        {:rows, Enum.reverse(rows)}

      {:done, rows} ->
        {:done, Enum.reverse(rows)}
    end
  end

  @spec last_insert_rowid(db()) :: {:ok, integer()}
  def last_insert_rowid(conn), do: Sqlite3NIF.last_insert_rowid(conn)

  @spec transaction_status(db()) :: {:ok, :idle | :transaction}
  def transaction_status(conn), do: Sqlite3NIF.transaction_status(conn)

  @doc """
  Causes the database connection to free as much memory as it can. This is
  useful if you are on a memory restricted system.
  """
  @spec shrink_memory(db()) :: :ok | {:error, reason()}
  def shrink_memory(conn) do
    Sqlite3NIF.execute(conn, String.to_charlist("PRAGMA shrink_memory"))
  end

  @spec fetch_all(db(), statement(), integer()) :: {:ok, [row()]} | {:error, reason()}
  def fetch_all(conn, statement, chunk_size) do
    fetch_all(conn, statement, chunk_size, [])
  end

  @spec fetch_all(db(), statement()) :: {:ok, [row()]} | {:error, reason()}
  def fetch_all(conn, statement) do
    # TODO: Should this be done in the NIF? It can be _much_ faster to build a
    # list there, but at the expense that it could block other dirty nifs from
    # getting work done.
    #
    # For now this just works
    chunk_size = Application.get_env(:exqlite, :default_chunk_size, 50)
    fetch_all(conn, statement, chunk_size, [])
  end

  defp fetch_all(conn, statement, chunk_size, accum) do
    case multi_step(conn, statement, chunk_size) do
      {:done, rows} ->
        {:ok, accum ++ rows}

      {:rows, rows} ->
        fetch_all(conn, statement, chunk_size, accum ++ rows)

      {:error, reason} ->
        {:error, reason}

      :busy ->
        {:error, "Database busy"}
    end
  end

  defp convert(%Date{} = val), do: Date.to_iso8601(val)
  defp convert(%DateTime{} = val), do: DateTime.to_iso8601(val)
  defp convert(%Time{} = val), do: Time.to_iso8601(val)
  defp convert(%NaiveDateTime{} = val), do: NaiveDateTime.to_iso8601(val)
  defp convert(val), do: val
end
