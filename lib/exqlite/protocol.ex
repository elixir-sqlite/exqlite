defmodule Exqlite.Protocol do
  @moduledoc """
  The driving protocol for sqlite3.
  """

  use DBConnection

  defstruct db: nil,
            db_path: nil,
            transaction_status: :idle

  alias Exqlite.Error
  alias Exqlite.Result
  alias Exqlite.Sqlite3

  @doc """
  Checks in the state to the connection process. Return `{:ok, state}`
  to allow the checkin or `{:disconnect, exception, state}` to disconnect.

  This callback is called when the control of the state is passed back
  to the connection process. It should reverse any changes to the
  connection state made in `c:checkout/1`.

  This callback is called in the connection process.
  """
  @impl true
  def checkin(state), do: {:ok, state}

  @doc """
  Checkouts the state from the connection process. Return `{:ok, state}`
  to allow the checkout or `{:disconnect, exception, state}` to disconnect.

  This callback is called when the control of the state is passed to
  another process. `c:checkin/1` is called with the new state when control
  is returned to the connection process.

  This callback is called in the connection process.
  """
  @impl true
  def checkout(state), do: {:ok, state}

  @doc """
  Called when the connection has been idle for a period of time. Return
  `{:ok, state}` to continue or `{:disconnect, exception, state}` to
  disconnect.

  This callback is called if no callbacks have been called after the
  idle timeout and a client process is not using the state. The idle
  timeout can be configured by the `:idle_interval` option. This function
  can be called whether the connection is checked in or checked out.

  This callback is called in the connection process.
  """
  @impl true
  def ping(state), do: {:ok, state}

  @doc """
  Connect to the database. Return `{:ok, state}` on success or
  `{:error, exception}` on failure.

  If an error is returned it will be logged and another
  connection attempt will be made after a backoff interval.

  This callback is called in the connection process.
  """
  @impl true
  def connect(options) do
    db_path = Keyword.fetch!(options, :database)

    case Sqlite3.open(db_path) do
      {:ok, db} ->
        {
          :ok,
          %__MODULE__{
            db: db,
            db_path: db_path,
            transaction_status: :idle
          }
        }

      {:error, reason} ->
        {:error, %Error{message: reason}}

      _ ->
        {:error, %Error{message: "unknown"}}
    end
  end

  @doc """
  Disconnect from the database. Return `:ok`.

  The exception as first argument is the exception from a `:disconnect`
  3-tuple returned by a previous callback.

  If the state is controlled by a client and it exits or takes too long
  to process a request the state will be last known state. In these
  cases the exception will be a `DBConnection.ConnectionError`.

  This callback is called in the connection process.
  """
  @impl true
  def disconnect(_error, %{db: db}) do
    Sqlite3.close(db)
    :ok
  end

  @doc """
  Handle the beginning of a transaction.

  Return `{:ok, result, state}` to continue, `{status, state}` to notify caller
  that the transaction can not begin due to the transaction status `status`,
  `{:error, exception, state}` (deprecated) to error without beginning the
  transaction, or `{:disconnect, exception, state}` to error and disconnect.

  A callback implementation should only return `status` if it
  can determine the database's transaction status without side effect.

  This callback is called in the client process.
  """
  @impl true
  def handle_begin(options, %{transaction_status: status} = state) do
    case Keyword.get(options, :mode, :transaction) do
      :transaction when status == :idle ->
        handle_transaction(:begin, "BEGIN", state)

      :savepoint when status == :transaction ->
        handle_transaction(:begin, "SAVEPOINT exqlite_savepoint", state)

      mode when mode in [:transaction, :savepoint] ->
        {status, state}
    end
  end

  @doc """
  Close a query prepared by `c:handle_prepare/3` with the database. Return
  `{:ok, result, state}` on success and to continue,
  `{:error, exception, state}` to return an error and continue, or
  `{:disconnect, exception, state}` to return an error and disconnect.

  This callback is called in the client process.
  """
  @impl true
  def handle_close(_query, _opts, state) do
    {:ok, nil, state}
  end

  @doc """
  Handle committing a transaction. Return `{:ok, result, state}` on successfully
  committing transaction, `{status, state}` to notify caller that the
  transaction can not commit due to the transaction status `status`,
  `{:error, exception, state}` (deprecated) to error and no longer be inside
  transaction, or `{:disconnect, exception, state}` to error and disconnect.

  A callback implementation should only return `status` if it
  can determine the database's transaction status without side effect.
  This callback is called in the client process.
  """
  @impl true
  def handle_commit(options, %{transaction_status: status} = state) do
    case Keyword.get(options, :mode, :transaction) do
      :transaction when status == :transaction ->
        handle_transaction(:commit, "COMMIT", state)

      :savepoint when status == :transaction ->
        handle_transaction(:commit, "RELEASE SAVEPOINT exqlite_savepoint", state)

      mode when mode in [:transaction, :savepoint] ->
        {status, state}
    end
  end

  @doc """
  Deallocate a cursor declared by `c:handle_declare/4` with the database. Return
  `{:ok, result, state}` on success and to continue,
  `{:error, exception, state}` to return an error and continue, or
  `{:disconnect, exception, state}` to return an error and disconnect.

  This callback is called in the client process.
  """
  @impl true
  def handle_deallocate(_query, _cursor, _opts, state) do
    {:error, %Error{message: "cursors not supported"}, state}
  end

  @doc """
  Declare a cursor using a query prepared by `c:handle_prepare/3`. Return
  `{:ok, query, cursor, state}` to return altered query `query` and cursor
  `cursor` for a stream and continue, `{:error, exception, state}` to return an
  error and continue or `{:disconnect, exception, state}` to return an error
  and disconnect.

  This callback is called in the client process.
  """
  @impl true
  def handle_declare(_query, _cursor, _opts, state) do
    # TODO: Explore building cursor like support
    {:error, %Error{message: "cursors not supported"}, state}
  end

  @doc """
  Execute a query prepared by `c:handle_prepare/3`. Return
  `{:ok, query, result, state}` to return altered query `query` and result
  `result` and continue, `{:error, exception, state}` to return an error and
  continue or `{:disconnect, exception, state}` to return an error and
  disconnect.

  This callback is called in the client process.
  """
  @impl true
  def handle_execute(_query, _params, _opts, state) do
    {:ok, nil, state}
  end

  @doc """
  Fetch the next result from a cursor declared by `c:handle_declare/4`. Return
  `{:cont, result, state}` to return the result `result` and continue using
  cursor, `{:halt, result, state}` to return the result `result` and close the
  cursor, `{:error, exception, state}` to return an error and close the
  cursor, `{:disconnect, exception, state}` to return an error and disconnect.

  This callback is called in the client process.
  """
  @impl true
  def handle_fetch(_query, _cursor, _opts, state) do
    {:error, :cursors_not_supported, state}
  end

  @doc """
  Prepare a query with the database. Return `{:ok, query, state}` where
  `query` is a query to pass to `execute/4` or `close/3`,
  `{:error, exception, state}` to return an error and continue or
  `{:disconnect, exception, state}` to return an error and disconnect.

  This callback is intended for cases where the state of a connection is
  needed to prepare a query and/or the query can be saved in the
  database to call later.

  This callback is called in the client process.
  """
  @impl true
  def handle_prepare(_query, _opts, state) do
    {:ok, nil, state}
  end

  @doc """
  Handle rolling back a transaction. Return `{:ok, result, state}` on successfully
  rolling back transaction, `{status, state}` to notify caller that the
  transaction can not rollback due to the transaction status `status`,
  `{:error, exception, state}` (deprecated) to
  error and no longer be inside transaction, or
  `{:disconnect, exception, state}` to error and disconnect.

  A callback implementation should only return `status` if it
  can determine the database' transaction status without side effect.

  This callback is called in the client and connection process.
  """
  @impl true
  def handle_rollback(options, %{transaction_status: transaction_status} = state) do
    case Keyword.get(options, :mode, :transaction) do
      :transaction when transaction_status == :transaction ->
        handle_transaction(:rollback, "ROLLBACK", state)

      :savepoint when transaction_status == :transaction ->
        with {:ok, _result, state} <-
               handle_transaction(
                 :rollback,
                 "ROLLBACK TO SAVEPOINT exqlite_savepoint",
                 state
               ) do
          handle_transaction(:rollback, "RELEASE SAVEPOINT exqlite_savepoint", state)
        end

      mode when mode in [:transaction, :savepoint] ->
        {transaction_status, state}
    end
  end

  @doc """
  Handle getting the transaction status. Return `{:idle, state}` if outside a
  transaction, `{:transaction, state}` if inside a transaction,
  `{:error, state}` if inside an aborted transaction, or
  `{:disconnect, exception, state}` to error and disconnect.

  If the callback returns a `:disconnect` tuples then `status/2` will return
  `:error`.
  """
  @impl true
  def handle_status(_opts, state) do
    {:idle, state}
  end

  defp handle_transaction(command, sql, %{db: db} = state) do
    case Sqlite3.execute(db, sql) do
      :ok ->
        {
          :ok,
          %Result{
            rows: nil,
            num_rows: nil,
            columns: nil,
            command: command
          },
          state
        }

      {:error, reason} ->
        {:error, %Error{message: reason}, state}

      _ ->
        {:error, %Error{message: "something went wrong"}, state}
    end
  end
end
