defmodule Exqlite.Sqlite3 do
  @moduledoc """
  The interface to the NIF implementation.
  """

  # If the database reference is closed, any prepared statements should be
  # dereferenced as well. It is entirely possible that an application does
  # not properly remove a stale reference.
  #
  # Will need to add a test for this and think of possible solution.

  # Need to figure out if we can just stream results where we use this
  # module as a sink.

  alias Exqlite.Flags
  alias Exqlite.Sqlite3NIF

  @type db() :: reference()
  @type statement() :: reference()
  @type reason() :: atom() | String.t()
  @type row() :: list()
  @type open_mode :: :readwrite | :readonly | :nomutex
  @type open_opt :: {:mode, :readwrite | :readonly | [open_mode()]}

  @doc """
  Opens a new sqlite database at the Path provided.

  `path` can be `":memory"` to keep the sqlite database in memory.

  ## Options

    * `:mode` - use `:readwrite` to open the database for reading and writing
      , `:readonly` to open it in read-only mode or `[:readonly | :readwrite, :nomutex]`
      to open it with no mutex mode. `:readwrite` will also create
      the database if it doesn't already exist. Defaults to `:readwrite`.
      Note: [:readwrite, :nomutex] is not recommended.
  """
  @spec open(String.t(), [open_opt()]) :: {:ok, db()} | {:error, reason()}
  def open(path, opts \\ []) do
    mode = Keyword.get(opts, :mode, :readwrite)
    Sqlite3NIF.open(path, flags_from_mode(mode))
  end

  defp flags_from_mode(:nomutex) do
    raise ArgumentError,
          "expected mode to be `:readwrite` or `:readonly`, can't use a single :nomutex mode"
  end

  defp flags_from_mode(:readwrite),
    do: do_flags_from_mode([:readwrite], [])

  defp flags_from_mode(:readonly),
    do: do_flags_from_mode([:readonly], [])

  defp flags_from_mode([_ | _] = modes),
    do: do_flags_from_mode(modes, [])

  defp flags_from_mode(mode) do
    raise ArgumentError,
          "expected mode to be `:readwrite`, `:readonly` or list of modes, but received #{inspect(mode)}"
  end

  defp do_flags_from_mode([:readwrite | tail], acc),
    do: do_flags_from_mode(tail, [:sqlite_open_readwrite, :sqlite_open_create | acc])

  defp do_flags_from_mode([:readonly | tail], acc),
    do: do_flags_from_mode(tail, [:sqlite_open_readonly | acc])

  defp do_flags_from_mode([:nomutex | tail], acc),
    do: do_flags_from_mode(tail, [:sqlite_open_nomutex | acc])

  defp do_flags_from_mode([mode | _tail], _acc) do
    raise ArgumentError,
          "expected mode to be `:readwrite`, `:readonly` or `:nomutex`, but received #{inspect(mode)}"
  end

  defp do_flags_from_mode([], acc),
    do: Flags.put_file_open_flags(acc)

  @doc """
  Closes the database and releases any underlying resources.
  """
  @spec close(db() | nil) :: :ok | {:error, reason()}
  def close(nil), do: :ok
  def close(conn), do: Sqlite3NIF.close(conn)

  @doc """
  Interrupt a long-running query.

  > #### Warning {: .warning}
  > If you are going to interrupt a long running process, it is unsafe to call
  > `close/1` immediately after. You run the risk of undefined behavior. This
  > is a limitation of the sqlite library itself. Please see the documentation
  > https://www.sqlite.org/c3ref/interrupt.html for more information.
  >
  > If close must be called after, it is best to put a short sleep in order to
  > let sqlite finish doing its book keeping.
  """
  @spec interrupt(db() | nil) :: :ok | {:error, reason()}
  def interrupt(nil), do: :ok
  def interrupt(conn), do: Sqlite3NIF.interrupt(conn)

  @doc """
  Executes an sql script. Multiple stanzas can be passed at once.
  """
  @spec execute(db(), String.t()) :: :ok | {:error, reason()}
  def execute(conn, sql), do: Sqlite3NIF.execute(conn, sql)

  @doc """
  Get the number of changes recently.

  **Note**: If triggers are used, the count may be larger than expected.

  See: https://sqlite.org/c3ref/changes.html
  """
  @spec changes(db()) :: {:ok, integer()} | {:error, reason()}
  def changes(conn), do: Sqlite3NIF.changes(conn)

  @spec prepare(db(), String.t()) :: {:ok, statement()} | {:error, reason()}
  def prepare(conn, sql), do: Sqlite3NIF.prepare(conn, sql)

  @doc """
  Resets a prepared statement.

  See: https://sqlite.org/c3ref/reset.html
  """
  @spec reset(statement) :: :ok
  def reset(stmt), do: Sqlite3NIF.reset(stmt)

  @doc """
  Returns number of SQL parameters in a prepared statement.

      iex> {:ok, conn} = Sqlite3.open(":memory:", [:readonly])
      iex> {:ok, stmt} = Sqlite3.prepare(conn, "SELECT ?, ?")
      iex> Sqlite3.bind_parameter_count(stmt)
      2

  """
  @spec bind_parameter_count(statement) :: integer
  def bind_parameter_count(stmt), do: Sqlite3NIF.bind_parameter_count(stmt)

  @type bind_value ::
          NaiveDateTime.t()
          | DateTime.t()
          | Date.t()
          | Time.t()
          | number
          | iodata
          | {:blob, iodata}
          | atom

  @doc """
  Resets a prepared statement and binds values to it.

      iex> {:ok, conn} = Sqlite3.open(":memory:", [:readonly])
      iex> {:ok, stmt} = Sqlite3.prepare(conn, "SELECT ?, ?, ?, ?, ?")
      iex> Sqlite3.bind(stmt, [42, 3.14, "Alice", {:blob, <<0, 0, 0>>}, nil])
      iex> Sqlite3.step(conn, stmt)
      {:row, [42, 3.14, "Alice", <<0, 0, 0>>, nil]}

      iex> {:ok, conn} = Sqlite3.open(":memory:", [:readonly])
      iex> {:ok, stmt} = Sqlite3.prepare(conn, "SELECT ?")
      iex> Sqlite3.bind(stmt, [42, 3.14, "Alice"])
      ** (ArgumentError) expected 1 arguments, got 3

      iex> {:ok, conn} = Sqlite3.open(":memory:", [:readonly])
      iex> {:ok, stmt} = Sqlite3.prepare(conn, "SELECT ?, ?")
      iex> Sqlite3.bind(stmt, [42])
      ** (ArgumentError) expected 2 arguments, got 1

      iex> {:ok, conn} = Sqlite3.open(":memory:", [:readonly])
      iex> {:ok, stmt} = Sqlite3.prepare(conn, "SELECT ?")
      iex> Sqlite3.bind(stmt, [:erlang.list_to_pid(~c"<0.0.0>")])
      ** (ArgumentError) unsupported type: #PID<0.0.0>

  """
  @spec bind(statement, [bind_value] | nil) :: :ok
  def bind(stmt, nil), do: bind(stmt, [])

  def bind(stmt, args) do
    params_count = bind_parameter_count(stmt)
    args_count = length(args)

    if args_count == params_count do
      bind_all(args, stmt, 1)
    else
      raise ArgumentError, "expected #{params_count} arguments, got #{args_count}"
    end
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp bind_all([param | params], stmt, idx) do
    case convert(param) do
      i when is_integer(i) -> bind_integer(stmt, idx, i)
      f when is_float(f) -> bind_float(stmt, idx, f)
      b when is_binary(b) -> bind_text(stmt, idx, b)
      b when is_list(b) -> bind_text(stmt, idx, IO.iodata_to_binary(b))
      nil -> bind_null(stmt, idx)
      :undefined -> bind_null(stmt, idx)
      a when is_atom(a) -> bind_text(stmt, idx, Atom.to_string(a))
      {:blob, b} when is_binary(b) -> bind_blob(stmt, idx, b)
      {:blob, b} when is_list(b) -> bind_blob(stmt, idx, IO.iodata_to_binary(b))
      _other -> raise ArgumentError, "unsupported type: #{inspect(param)}"
    end

    bind_all(params, stmt, idx + 1)
  end

  defp bind_all([], _stmt, _idx), do: :ok

  @spec columns(db(), statement()) :: {:ok, [binary()]} | {:error, reason()}
  def columns(conn, statement), do: Sqlite3NIF.columns(conn, statement)

  @spec step(db(), statement()) :: :done | :busy | {:row, row()} | {:error, reason()}
  def step(conn, statement), do: Sqlite3NIF.step(conn, statement)

  @spec multi_step(db(), statement()) ::
          :busy | {:rows, [row()]} | {:done, [row()]} | {:error, reason()}
  def multi_step(conn, statement) do
    chunk_size = Application.get_env(:exqlite, :default_chunk_size, 50)
    multi_step(conn, statement, chunk_size)
  end

  @spec multi_step(db(), statement(), integer()) ::
          :busy | {:rows, [row()]} | {:done, [row()]} | {:error, reason()}
  def multi_step(conn, statement, chunk_size) do
    case Sqlite3NIF.multi_step(conn, statement, chunk_size) do
      :busy ->
        :busy

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
    Sqlite3NIF.execute(conn, "PRAGMA shrink_memory")
  end

  @spec fetch_all(db(), statement(), integer()) :: {:ok, [row()]} | {:error, reason()}
  def fetch_all(conn, statement, chunk_size) do
    {:ok, try_fetch_all(conn, statement, chunk_size)}
  catch
    :throw, {:error, _reason} = error -> error
  end

  defp try_fetch_all(conn, statement, chunk_size) do
    case multi_step(conn, statement, chunk_size) do
      {:done, rows} -> rows
      {:rows, rows} -> rows ++ try_fetch_all(conn, statement, chunk_size)
      {:error, _reason} = error -> throw(error)
      :busy -> throw({:error, "Database busy"})
    end
  end

  @spec fetch_all(db(), statement()) :: {:ok, [row()]} | {:error, reason()}
  def fetch_all(conn, statement) do
    # Should this be done in the NIF? It can be _much_ faster to build a list
    # there, but at the expense that it could block other dirty nifs from
    # getting work done.
    #
    # For now this just works
    chunk_size = Application.get_env(:exqlite, :default_chunk_size, 50)
    fetch_all(conn, statement, chunk_size)
  end

  @doc """
  Serialize the contents of the database to a binary.
  """
  @spec serialize(db(), String.t()) :: {:ok, binary()} | {:error, reason()}
  def serialize(conn, database \\ "main") do
    Sqlite3NIF.serialize(conn, database)
  end

  @doc """
  Disconnect from database and then reopen as an in-memory database based on
  the serialized binary.
  """
  @spec deserialize(db(), String.t(), binary()) :: :ok | {:error, reason()}
  def deserialize(conn, database \\ "main", serialized) do
    Sqlite3NIF.deserialize(conn, database, serialized)
  end

  def release(_conn, nil), do: :ok

  @doc """
  Once finished with the prepared statement, call this to release the underlying
  resources.

  This should be called whenever you are done operating with the prepared statement. If
  the system has a high load the garbage collector may not clean up the prepared
  statements in a timely manner and causing higher than normal levels of memory
  pressure.

  If you are operating on limited memory capacity systems, definitely call this.
  """
  @spec release(db(), statement()) :: :ok | {:error, reason()}
  def release(conn, statement) do
    Sqlite3NIF.release(conn, statement)
  end

  @doc """
  Allow loading native extensions.
  """
  @spec enable_load_extension(db(), boolean()) :: :ok | {:error, reason()}
  def enable_load_extension(conn, flag) do
    if flag do
      Sqlite3NIF.enable_load_extension(conn, 1)
    else
      Sqlite3NIF.enable_load_extension(conn, 0)
    end
  end

  @doc """
  Send data change notifications to a process.

  Each time an insert, update, or delete is performed on the connection provided
  as the first argument, a message will be sent to the pid provided as the second argument.

  The message is of the form: `{action, db_name, table, row_id}`, where:

    * `action` is one of `:insert`, `:update` or `:delete`
    * `db_name` is a string representing the database name where the change took place
    * `table` is a string representing the table name where the change took place
    * `row_id` is an integer representing the unique row id assigned by SQLite

  ## Restrictions

    * There are some conditions where the update hook will not be invoked by SQLite.
      See the documentation for [more details](https://www.sqlite.org/c3ref/update_hook.html)
    * Only one pid can listen to the changes on a given database connection at a time.
      If this function is called multiple times for the same connection, only the last pid will
      receive the notifications
    * Updates only happen for the connection that is opened. For example, there
      are two connections A and B. When an update happens on connection B, the
      hook set for connection A will not receive the update, but the hook for
      connection B will receive the update.
  """
  @spec set_update_hook(db(), pid()) :: :ok | {:error, reason()}
  def set_update_hook(conn, pid) do
    Sqlite3NIF.set_update_hook(conn, pid)
  end

  @doc """
  Send log messages to a process.

  Each time a message is logged in SQLite a message will be sent to the pid provided as the argument.

  The message is of the form: `{:log, rc, message}`, where:

    * `rc` is an integer [result code](https://www.sqlite.org/rescode.html) or an [extended result code](https://www.sqlite.org/rescode.html#extrc)
    * `message` is a string representing the log message

  See [`SQLITE_CONFIG_LOG`](https://www.sqlite.org/c3ref/c_config_covering_index_scan.html) and
  ["The Error And Warning Log"](https://www.sqlite.org/errlog.html) for more details.

  ## Restrictions

    * Only one pid can listen to the log messages at a time.
      If this function is called multiple times, only the last pid will
      receive the notifications
  """
  @spec set_log_hook(pid()) :: :ok | {:error, reason()}
  def set_log_hook(pid) do
    Sqlite3NIF.set_log_hook(pid)
  end

  @sqlite_ok 0

  @doc """
  Binds a text value to a prepared statement.

      iex> {:ok, conn} = Sqlite3.open(":memory:", [:readonly])
      iex> {:ok, stmt} = Sqlite3.prepare(conn, "SELECT ?")
      iex> Sqlite3.bind_text(stmt, 1, "Alice")
      :ok

  """
  @spec bind_text(statement, non_neg_integer, String.t()) :: :ok
  def bind_text(stmt, index, text) do
    case Sqlite3NIF.bind_text(stmt, index, text) do
      @sqlite_ok -> :ok
      rc -> raise Exqlite.Error, message: errmsg(stmt) || errstr(rc)
    end
  end

  @doc """
  Binds a blob value to a prepared statement.

      iex> {:ok, conn} = Sqlite3.open(":memory:", [:readonly])
      iex> {:ok, stmt} = Sqlite3.prepare(conn, "SELECT ?")
      iex> Sqlite3.bind_blob(stmt, 1, <<0, 0, 0>>)
      :ok

  """
  @spec bind_blob(statement, non_neg_integer, binary) :: :ok
  def bind_blob(stmt, index, blob) do
    case Sqlite3NIF.bind_blob(stmt, index, blob) do
      @sqlite_ok -> :ok
      rc -> raise Exqlite.Error, message: errmsg(stmt) || errstr(rc)
    end
  end

  @doc """
  Binds an integer value to a prepared statement.

      iex> {:ok, conn} = Sqlite3.open(":memory:", [:readonly])
      iex> {:ok, stmt} = Sqlite3.prepare(conn, "SELECT ?")
      iex> Sqlite3.bind_integer(stmt, 1, 42)
      :ok

  """
  @spec bind_integer(statement, non_neg_integer, integer) :: :ok
  def bind_integer(stmt, index, integer) do
    case Sqlite3NIF.bind_integer(stmt, index, integer) do
      @sqlite_ok -> :ok
      rc -> raise Exqlite.Error, message: errmsg(stmt) || errstr(rc)
    end
  end

  @doc """
  Binds a float value to a prepared statement.

      iex> {:ok, conn} = Sqlite3.open(":memory:", [:readonly])
      iex> {:ok, stmt} = Sqlite3.prepare(conn, "SELECT ?")
      iex> Sqlite3.bind_float(stmt, 1, 3.14)
      :ok

  """
  @spec bind_float(statement, non_neg_integer, float) :: :ok
  def bind_float(stmt, index, float) do
    case Sqlite3NIF.bind_float(stmt, index, float) do
      @sqlite_ok -> :ok
      rc -> raise Exqlite.Error, message: errmsg(stmt) || errstr(rc)
    end
  end

  @doc """
  Binds a null value to a prepared statement.

      iex> {:ok, conn} = Sqlite3.open(":memory:", [:readonly])
      iex> {:ok, stmt} = Sqlite3.prepare(conn, "SELECT ?")
      iex> Sqlite3.bind_null(stmt, 1)
      :ok

  """
  @spec bind_null(statement, non_neg_integer) :: :ok
  def bind_null(stmt, index) do
    case Sqlite3NIF.bind_null(stmt, index) do
      @sqlite_ok -> :ok
      rc -> raise Exqlite.Error, message: errmsg(stmt) || errstr(rc)
    end
  end

  defp errmsg(stmt), do: Sqlite3NIF.errmsg(stmt)
  defp errstr(rc), do: Sqlite3NIF.errstr(rc)

  defp convert(%Date{} = val), do: Date.to_iso8601(val)
  defp convert(%Time{} = val), do: Time.to_iso8601(val)
  defp convert(%NaiveDateTime{} = val), do: NaiveDateTime.to_iso8601(val)
  defp convert(%DateTime{time_zone: "Etc/UTC"} = val), do: NaiveDateTime.to_iso8601(val)

  defp convert(%DateTime{} = datetime) do
    raise ArgumentError, "#{inspect(datetime)} is not in UTC"
  end

  defp convert(val), do: val
end
