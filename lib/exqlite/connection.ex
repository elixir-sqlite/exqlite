defmodule Exqlite.Connection do
  @moduledoc """
  The adapter for an Ecto connection.
  """

  @behaviour Ecto.Adapters.SQL.Connection

  @impl true
  def child_spec(opts) do
    {:ok, _} = Application.ensure_all_started(:db_connection)
    DBConnection.child_spec(Exqlite.Protocol, opts)
  end

  @impl true
  def ddl_logs(_), do: []

  @impl true
  def all(%Ecto.Query{lock: lock}) when lock != nil do
    raise ArgumentError, "locks are not supported by SQLite"
  end

  @impl true
  def all(_query) do
    []
  end
end
