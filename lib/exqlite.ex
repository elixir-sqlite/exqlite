defmodule Exqlite do
  @moduledoc """
  SQLite3 driver for Elixir.
  """

  alias Exqlite.{Nif, SQLiteError, UsageError}

  @type conn :: reference()
  @type stmt :: reference()
  @type bind_arg :: atom | binary | number | {:blob, binary}
  @type returned_row :: [number | binary | nil]
  @type error :: SQLiteError.t() | UsageError.t()

  # https://www.sqlite.org/c3ref/c_open_autoproxy.html
  open_flag_mappings = [
    readonly: 0x00000001,
    readwrite: 0x00000002,
    create: 0x00000004,
    deleteonclose: 0x00000008,
    exclusive: 0x00000010,
    autoproxy: 0x00000020,
    uri: 0x00000040,
    memory: 0x00000080,
    main_db: 0x00000100,
    temp_db: 0x00000200,
    transient_db: 0x00000400,
    main_journal: 0x00000800,
    temp_journal: 0x00001000,
    subjournal: 0x00002000,
    super_journal: 0x00004000,
    nomutex: 0x00008000,
    fullmutex: 0x00010000,
    sharedcache: 0x00020000,
    privatecache: 0x00040000,
    wal: 0x00080000,
    nofollow: 0x01000000,
    exrescode: 0x02000000
  ]

  open_flag_names = Enum.map(open_flag_mappings, fn {name, _value} -> name end)
  open_flag_union = Enum.reduce(open_flag_names, &{:|, [], [&1, &2]})
  @type open_flag :: unquote(open_flag_union)

  for {name, value} <- open_flag_mappings do
    defp open_flag_value(unquote(name)), do: unquote(value)
  end

  @default_open_flags [:readwrite, :create, :exrescode]

  @doc """
  Opens a new sqlite database at the Path provided.
  `path` can be `":memory"` to keep the sqlite database in memory.

  ## Options

  * `:flags` - flags to use to open the database for reading and writing.
      Defaults to `#{inspect(@default_open_flags)}`.
      See https://www.sqlite.org/c3ref/c_open_autoproxy.html for more options.

  """
  @spec open(String.t(), [open_flag]) :: {:ok, conn} | {:error, error}
  def open(path, flags \\ @default_open_flags) do
    path = String.to_charlist(path)

    flags =
      Enum.reduce(flags, 0, fn flag, acc ->
        Bitwise.bor(acc, open_flag_value(flag))
      end)

    wrap_error(Nif.open(path, flags))
  end

  @doc """
  Closes the database and releases any underlying resources.
  """
  @spec close(conn) :: :ok | {:error, error}
  def close(conn), do: wrap_error(Nif.close(conn))

  @doc """
  Executes an sql script. Multiple stanzas can be passed at once.
  """
  @spec execute(conn, iodata) :: :ok | {:error, error}
  def execute(conn, sql), do: wrap_error(Nif.execute(conn, sql))

  @doc """
  Get the number of changes recently.

  **Note**: If triggers are used, the count may be larger than expected.

  See: https://sqlite.org/c3ref/changes.html
  """
  @spec changes(conn) :: {:ok, non_neg_integer} | {:error, error}
  def changes(conn), do: wrap_error(Nif.changes(conn))

  @doc """
  Prepares an SQL statement.
  """
  @spec prepare(conn, iodata) :: {:ok, stmt} | {:error, error}
  def prepare(conn, sql), do: wrap_error(Nif.prepare(conn, sql))

  @doc """
  Binds values to a prepared SQL statement.
  """
  @spec bind(conn, stmt, [bind_arg]) :: :ok | {:error, error}
  def bind(conn, stmt, args), do: wrap_error(Nif.bind(conn, stmt, args))

  @doc """
  Reads the column names returned by a prepared SQL statement.
  """
  @spec columns(conn, stmt) :: {:ok, [String.t()]} | {:error, error}
  def columns(conn, stmt), do: wrap_error(Nif.columns(conn, stmt))

  @doc """
  Performs a single step through a prepared SQL statement.
  """
  @spec step(conn, stmt) :: {:row, returned_row} | :done | {:error, error}
  def step(conn, stmt), do: wrap_error(Nif.step(conn, stmt))

  @doc """
  Interrupts a long-running query.
  """
  @spec interrupt(conn) :: :ok | {:error, error}
  def interrupt(conn), do: wrap_error(Nif.interrupt(conn))

  @doc """
  Performs multiple steps through a prepared SQL statement in a single NIF call.
  """
  @spec multi_step(conn, stmt, pos_integer) ::
          {:rows, [returned_row]} | {:done, [returned_row]} | {:error, error}
  def multi_step(conn, stmt, max_rows) do
    case Nif.multi_step(conn, stmt, max_rows) do
      {:rows, rows} -> {:rows, :lists.reverse(rows)}
      {:done, rows} -> {:done, :lists.reverse(rows)}
      error -> wrap_error(error)
    end
  end

  @doc """
  Reads the last inserted ROWID from the connection.
  """
  @spec last_insert_rowid(conn) :: {:ok, integer} | {:error, error}
  def last_insert_rowid(conn), do: wrap_error(Nif.last_insert_rowid(conn))

  @doc """
  Reads the transactions status of the connection.
  """
  @spec transaction_status(conn) :: {:ok, :idle | :transaction} | {:error, error}
  def transaction_status(conn), do: wrap_error(Nif.transaction_status(conn))

  @doc """
  Fetches all rows from a prepared statement in batches of `max_rows` per NIF call.
  """
  @spec fetch_all(conn, stmt, pos_integer) ::
          {:ok, [returned_row]} | {:error, error}
  def fetch_all(conn, stmt, max_rows \\ 50) when is_reference(stmt) do
    {:ok, try_fetch_all(conn, stmt, max_rows)}
  catch
    :throw, error -> error
  end

  defp try_fetch_all(conn, stmt, max_rows) do
    case multi_step(conn, stmt, max_rows) do
      {:done, rows} -> rows
      {:rows, rows} -> rows ++ try_fetch_all(conn, stmt, max_rows)
      error -> throw(error)
    end
  end

  # TODO document once the write counterpart is ready
  @doc false
  @spec prepare_fetch_all(conn, iodata, [bind_arg], pos_integer) ::
          {:ok, [returned_row]} | {:error, error}
  def prepare_fetch_all(conn, sql, args \\ [], max_rows \\ 50) do
    with {:ok, stmt} <- prepare(conn, sql) do
      try do
        with :ok <- bind(conn, stmt, args) do
          fetch_all(conn, stmt, max_rows)
        end
      after
        :ok = release(stmt)
      end
    end
  end

  @doc """
  Serialize the contents of the database to a binary.
  """
  @spec serialize(conn, String.t()) :: {:ok, binary} | {:error, error}
  def serialize(conn, database \\ "main") do
    wrap_error(Nif.serialize(conn, to_charlist(database)))
  end

  @doc """
  Disconnect from database and then reopen as an in-memory database based on
  the serialized binary.
  """
  @spec deserialize(conn, String.t(), binary) :: :ok | {:error, error}
  def deserialize(conn, database \\ "main", serialized) do
    wrap_error(Nif.deserialize(conn, to_charlist(database), serialized))
  end

  @doc """
  Once finished with the prepared statement, call this to release the underlying
  resources.

  This should be called whenever you are done operating with the prepared statement. If
  the system has a high load the garbage collector may not clean up the prepared
  statements in a timely manner and causing higher than normal levels of memory
  pressure.

  If you are operating on limited memory capacity systems, definitely call this.
  """
  @spec release(stmt) :: :ok | {:error, error}
  def release(stmt), do: wrap_error(Nif.release(stmt))

  @doc """
  Allow loading native extensions.
  """
  @spec enable_load_extension(conn) :: :ok | {:error, error}
  def enable_load_extension(conn), do: wrap_error(Nif.enable_load_extension(conn, 1))

  @doc """
  Forbid loading native extensions.
  """
  @spec disable_load_extension(conn) :: :ok | {:error, error}
  def disable_load_extension(conn), do: wrap_error(Nif.enable_load_extension(conn, 0))

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
  @spec set_update_hook(conn, pid) :: :ok | {:error, error}
  def set_update_hook(conn, pid), do: wrap_error(Nif.set_update_hook(conn, pid))

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
  @spec set_log_hook(pid) :: :ok | {:error, error}
  def set_log_hook(pid), do: wrap_error(Nif.set_log_hook(pid))

  # TODO sql / statement
  @compile inline: [wrap_error: 1]
  defp wrap_error({:error, rc, message}) do
    {:error, SQLiteError.exception(rc: rc, message: message)}
  end

  defp wrap_error({:error, {:wrong_type, value}}) do
    message = "unsupported type for bind: " <> inspect(value)
    {:error, UsageError.exception(message: message)}
  end

  defp wrap_error({:error, reason}) when is_atom(reason) do
    {:error, UsageError.exception(message: reason)}
  end

  defp wrap_error(success), do: success
end
