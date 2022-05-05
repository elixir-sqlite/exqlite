defmodule Exqlite do
  @moduledoc """
  SQLite3 driver for Elixir.
  """

  alias Exqlite.Connection
  alias Exqlite.Error
  alias Exqlite.Query
  alias Exqlite.Result

  @doc "See `Exqlite.Connection.connect/1`"
  @spec start_link([Connection.connection_opt()]) :: {:ok, pid()} | {:error, Error.t()}
  def start_link(opts) do
    DBConnection.start_link(Connection, opts)
  end

  @spec query(DBConnection.conn(), iodata(), list(), list()) ::
          {:ok, Result.t()} | {:error, Exception.t()}
  def query(conn, statement, params \\ [], opts \\ []) do
    query = %Query{name: "", statement: IO.iodata_to_binary(statement)}

    case DBConnection.prepare_execute(conn, query, params, opts) do
      {:ok, _query, result} ->
        {:ok, result}

      otherwise ->
        otherwise
    end
  end

  @spec query!(DBConnection.conn(), iodata(), list(), list()) :: Result.t()
  def query!(conn, statement, params \\ [], opts \\ []) do
    case query(conn, statement, params, opts) do
      {:ok, result} -> result
      {:error, err} -> raise err
    end
  end

  @spec prepare(DBConnection.conn(), iodata(), list()) ::
          {:ok, Query.t()} | {:error, Exception.t()}
  def prepare(conn, name, statement, opts \\ []) do
    query = %Query{name: name, statement: statement}
    DBConnection.prepare(conn, query, opts)
  end

  @spec prepare!(DBConnection.conn(), iodata(), iodata(), list()) :: Query.t()
  def prepare!(conn, name, statement, opts \\ []) do
    query = %Query{name: name, statement: statement}
    DBConnection.prepare!(conn, query, opts)
  end

  @spec prepare_execute(DBConnection.conn(), iodata(), iodata(), list(), list()) ::
          {:ok, Query.t(), Result.t()} | {:error, Error.t()}
  def prepare_execute(conn, name, statement, params, opts \\ []) do
    query = %Query{name: name, statement: statement}
    DBConnection.prepare_execute(conn, query, params, opts)
  end

  @spec prepare_execute!(DBConnection.conn(), iodata(), iodata(), list(), list()) ::
          {Query.t(), Result.t()}
  def prepare_execute!(conn, name, statement, params, opts \\ []) do
    query = %Query{name: name, statement: statement}
    DBConnection.prepare_execute!(conn, query, params, opts)
  end

  @spec execute(DBConnection.conn(), Query.t(), list(), list()) ::
          {:ok, Result.t()} | {:error, Error.t()}
  def execute(conn, query, params, opts \\ []) do
    DBConnection.execute(conn, query, params, opts)
  end

  @spec execute!(DBConnection.conn(), Query.t(), list(), list()) :: Result.t()
  def execute!(conn, query, params, opts \\ []) do
    DBConnection.execute!(conn, query, params, opts)
  end

  @spec close(DBConnection.conn(), Query.t(), list()) :: :ok | {:error, Exception.t()}
  def close(conn, query, opts \\ []) do
    with {:ok, _} <- DBConnection.close(conn, query, opts) do
      :ok
    end
  end

  @spec close!(DBConnection.conn(), Query.t(), list()) :: :ok
  def close!(conn, query, opts \\ []) do
    DBConnection.close!(conn, query, opts)
    :ok
  end

  @spec transaction(DBConnection.conn(), (DBConnection.t() -> result), list()) ::
          {:ok, result} | {:error, any}
        when result: var
  def transaction(conn, fun, opts \\ []) do
    DBConnection.transaction(conn, fun, opts)
  end

  @spec rollback(DBConnection.t(), term()) :: no_return()
  def rollback(conn, reason), do: DBConnection.rollback(conn, reason)

  @spec child_spec([Connection.connection_opt()]) :: :supervisor.child_spec()
  def child_spec(opts) do
    DBConnection.child_spec(Connection, opts)
  end
end
