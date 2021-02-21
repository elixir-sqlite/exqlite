defmodule Exqlite.Sqlite3 do
  @moduledoc """
  The interface to the NIF implementation.
  """

  alias Exqlite.Sqlite3NIF

  @type db() :: reference()
  @type statement() :: reference()
  @type reason() :: atom() | String.t()

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
  @spec execute(db(), String.t()) :: :ok | {:error, {atom(), reason()}}
  def execute(conn, sql) do
    case Sqlite3NIF.execute(conn, String.to_charlist(sql)) do
      :ok ->
        :ok

      {:error, {code, reason}} ->
        {:error, {code, String.Chars.to_string(reason)}}

      _ ->
        # This should never happen, but just to be safe
        {:error, {:unknown, "unhandled error"}}
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

  @spec bind(db(), statement(), nil) ::
          :ok | {:error, reason()} | {:error, {atom(), any()}}
  def bind(conn, statement, nil), do: bind(conn, statement, [])

  @spec bind(db(), statement(), []) ::
          :ok | {:error, reason()} | {:error, {atom(), any()}}
  def bind(conn, statement, args) do
    Sqlite3NIF.bind(conn, statement, Enum.map(args, &convert/1))
  end

  @spec finalize(db(), statement()) :: :ok | {:error, reason()}
  def finalize(conn, statement), do: Sqlite3NIF.finalize(conn, statement)

  @spec columns(db(), statement()) :: {:ok, []} | {:error, reason()}
  def columns(conn, statement), do: Sqlite3NIF.columns(conn, statement)

  @spec step(db(), statement()) :: :done | :busy | {:row, []}
  def step(conn, statement), do: Sqlite3NIF.step(conn, statement)

  @spec last_insert_rowid(db()) :: {:ok, integer()}
  def last_insert_rowid(conn), do: Sqlite3NIF.last_insert_rowid(conn)

  defp convert(%Date{} = val), do: Date.to_iso8601(val)
  defp convert(%DateTime{} = val), do: DateTime.to_iso8601(val)
  defp convert(%Time{} = val), do: Time.to_iso8601(val)
  defp convert(%NaiveDateTime{} = val), do: NaiveDateTime.to_iso8601(val)
  defp convert(val), do: val
end
