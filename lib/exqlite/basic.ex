defmodule Exqlite.Basic do
  @moduledoc """
  A very basis API without lots of options to allow simpler usage for basic needs.
  """

  alias Exqlite.Sqlite3
  alias Exqlite.Error

  def open(path) do
    Sqlite3.open(path)
  end

  def close(db) do
    case Sqlite3.close(db) do
      :ok -> :ok
      {:error, reason} -> {:error, Error.exception(message: to_string(reason))}
    end
  end

  def exec(db, stmt, args \\ []) do
    with {:ok, stmt} <- Sqlite3.prepare(db, stmt),
         :ok <- maybe_bind(db, stmt, args),
         {:ok, columns} <- Sqlite3.columns(db, stmt),
         {:ok, rows} <- Sqlite3.fetch_all(db, stmt),
         do: {:ok, rows, columns}
  end

  def load_extension(db, path) do
    exec(db, "select load_extension(?)", [path])
  end

  def enable_load_extension(db) do
    Sqlite3.enable_load_extension(db, true)
  end

  def disable_load_extension(db) do
    Sqlite3.enable_load_extension(db, false)
  end

  defp maybe_bind(_db, _stmt, []), do: :ok
  defp maybe_bind(db, stmt, params), do: Sqlite3.bind(db, stmt, params)
end
