defmodule Exqlite do
  @moduledoc """
  SQLite3 driver for Elixir.
  """

  alias Exqlite.RWConnection
  alias Exqlite.Result

  @doc "See `Exqlite.RWConnection.start_link/1`"
  def start_link(opts), do: RWConnection.start_link(opts)
  def child_spec(opts), do: RWConnection.child_spec(opts)

  @spec query(RWConnection.t(), iodata(), list()) ::
          {:ok, Result.t()} | {:error, Exception.t()}
  def query(conn, statement, params \\ []) do
    RWConnection.query(conn, statement, params)
  end

  @spec query!(RWConnection.t(), iodata(), list()) :: Result.t()
  def query!(conn, statement, params \\ []) do
    case query(conn, statement, params) do
      {:ok, result} -> result
      {:error, err} -> raise err
    end
  end
end
