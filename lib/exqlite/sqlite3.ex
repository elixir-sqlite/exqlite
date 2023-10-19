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
  @type open_opt :: {:mode, :readwrite | :readonly}

  @doc """
  Opens a new sqlite database at the Path provided.

  `path` can be `":memory"` to keep the sqlite database in memory.

  ## Options

    * `:mode` - use `:readwrite` to open the database for reading and writing
      or `:readonly` to open it in read-only mode. `:readwrite` will also create
      the database if it doesn't already exist. Defaults to `:readwrite`.
  """
  @spec open(String.t(), [open_opt()]) :: {:ok, db()} | {:error, reason()}
  def open(path, opts \\ []) do
    mode = Keyword.get(opts, :mode, :readwrite)
    Sqlite3NIF.open(String.to_charlist(path), flags_from_mode(mode))
  end

  defp flags_from_mode(:readwrite),
    do: Flags.put_file_open_flags([:sqlite_open_readwrite, :sqlite_open_create])

  defp flags_from_mode(:readonly),
    do: Flags.put_file_open_flags([:sqlite_open_readonly])

  defp flags_from_mode(mode) do
    raise ArgumentError,
          "expected mode to be `:readwrite` or `:readonly`, but received #{inspect(mode)}"
  end

  @doc """
  Closes the database and releases any underlying resources.
  """
  @spec close(db() | nil) :: :ok | {:error, reason()}
  def close(nil), do: :ok
  def close(conn), do: Sqlite3NIF.close(conn)

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

  @spec bind(db(), statement(), nil) :: :ok | {:error, reason()}
  def bind(conn, statement, nil), do: bind(conn, statement, [])

  @spec bind(db(), statement(), list()) :: :ok | {:error, reason()}
  def bind(conn, statement, args) do
    Sqlite3NIF.bind(conn, statement, Enum.map(args, &convert/1))
  end

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
    Sqlite3NIF.execute(conn, String.to_charlist("PRAGMA shrink_memory"))
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
    Sqlite3NIF.serialize(conn, String.to_charlist(database))
  end

  @doc """
  Disconnect from database and then reopen as an in-memory database based on
  the serialized binary.
  """
  @spec deserialize(db(), String.t(), binary()) :: :ok | {:error, reason()}
  def deserialize(conn, database \\ "main", serialized) do
    Sqlite3NIF.deserialize(conn, String.to_charlist(database), serialized)
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

  defp convert(%Date{} = val), do: Date.to_iso8601(val)
  defp convert(%Time{} = val), do: Time.to_iso8601(val)
  defp convert(%NaiveDateTime{} = val), do: NaiveDateTime.to_iso8601(val)
  defp convert(%DateTime{time_zone: "Etc/UTC"} = val), do: NaiveDateTime.to_iso8601(val)

  defp convert(%DateTime{} = datetime) do
    raise ArgumentError, "#{inspect(datetime)} is not in UTC"
  end

  defp convert(val), do: val
end
