defmodule Exqlite do
  @moduledoc """
  SQLite3 driver for Elixir.
  """

  alias Exqlite.{Nif, Error}

  @type db :: reference()
  @type stmt :: reference()
  @type row :: [binary | number | nil]
  @type error :: {:error, Error.t()}

  # https://www.sqlite.org/c3ref/c_open_autoproxy.html
  open_flags = [
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

  open_flag_names = Enum.map(open_flags, fn {name, _value} -> name end)
  open_flag_union = Enum.reduce(open_flag_names, &{:|, [], [&1, &2]})
  @type open_flag :: unquote(open_flag_union)

  for {name, value} <- open_flags do
    defp open_flag(unquote(name)), do: unquote(value)
  end

  defp open_flag(invalid) do
    raise ArgumentError, "invalid flag: #{inspect(invalid)}"
  end

  @doc """
  Opens a new SQLite database at the path provided.

  - `path` can be `":memory"` to keep the sqlite database in memory
  - `flags` are listed in https://www.sqlite.org/c3ref/c_open_autoproxy.html

  The flags parameter must include, at a minimum, one of the following three flag combinations:

  - `:readwrite` and `:create`
  - `:readonly`
  - `:readwrite`

  Examples:

      # TODO explain
      Exqlite.open("test.db", [:readwrite, :create])

      # TODO explain
      Exqlite.open("file://test.db?", [:readonly, :uri])

      # TODO explain
      Exqlite.open(":memory:", [:readwrite, :create, :exrescode])

  See: https://sqlite.org/c3ref/open.html
  """
  @spec open(Path.t(), [open_flag]) :: {:ok, db} | error
  def open(path, flags) do
    flags =
      Enum.reduce(flags, 0, fn flag, acc ->
        Bitwise.bor(acc, open_flag(flag))
      end)

    # TODO vfs
    wrap_error(Nif.dirty_io_open(path, flags))
  end

  @doc """
  Closes the database and releases any underlying resources.

  See: https://sqlite.org/c3ref/close.html
  """
  @spec close(db) :: :ok | error
  def close(db), do: wrap_error(Nif.dirty_io_close(db))

  @doc """
  Interrupts a long-running query.

  See: https://sqlite.org/c3ref/interrupt.html
  """
  @spec interrupt(db) :: :ok | error
  def interrupt(db), do: wrap_error(Nif.interrupt(db))

  @doc """
  Executes an sql script. Multiple stanzas can be passed at once.

  See: https://sqlite.org/c3ref/exec.html
  """
  @spec execute(db, iodata) :: :ok | error
  def execute(db, sql), do: wrap_error(Nif.execute(db, sql))

  @doc """
  Gets the number of changes recently.

  **Note**: If triggers are used, the count may be larger than expected.

  See: https://sqlite.org/c3ref/changes.html
  """
  @spec changes(db) :: {:ok, integer} | error
  def changes(db), do: wrap_error(Nif.changes(db))

  @doc """
  Prepares a statement for execution.

  See: https://sqlite.org/c3ref/prepare.html
  """
  @spec prepare(db, iodata) :: {:ok, stmt} | error
  def prepare(db, sql), do: wrap_error(Nif.prepare(db, sql))

  @doc "Same as `prepare/2` but runs on DIRTY IO scheduler."
  @spec dirty_cpu_prepare(db, iodata) :: {:ok, stmt} | error
  def dirty_cpu_prepare(db, sql), do: wrap_error(Nif.dirty_cpu_prepare(db, sql))

  @doc """
  Binds the arguments to the prepared statement.

  See: https://www.sqlite.org/c3ref/bind_blob.html
  """
  @spec bind_all(db, stmt, [binary | number | nil]) :: :ok | error
  def bind_all(conn, statement, args) do
    wrap_error(Nif.bind_all(conn, statement, args))
  end

  @doc "Same as ``bind_all/3`` but runs on dirty CPU scheduler."
  @spec dirty_cpu_bind_all(db, stmt, [binary | number | nil]) :: :ok | error
  def dirty_cpu_bind_all(conn, statement, args) do
    wrap_error(Nif.dirty_cpu_bind_all(conn, statement, args))
  end

  @doc """
  Returns the columns in the result set.

  See:
  - https://www.sqlite.org/c3ref/column_count.html
  - https://www.sqlite.org/c3ref/column_name.html
  """
  @spec columns(db, stmt) :: {:ok, [String.t()]} | error
  def columns(db, stmt), do: wrap_error(Nif.columns(db, stmt))

  @doc """
  Executes the prepared statement once.

  See: https://sqlite.org/c3ref/step.html
  """
  @spec step(db, stmt) :: {:row, row} | :done | error
  def step(db, stmt), do: wrap_error(Nif.step(db, stmt))

  @doc "Same as `step/2` but runs on dirty IO scheduler."
  @spec dirty_io_step(db, stmt) :: {:row, row} | :done | error
  def dirty_io_step(db, stmt), do: wrap_error(Nif.dirty_io_step(db, stmt))

  @doc """
  Returns the rowid of the most recent successful INSERT.

  See: https://sqlite.org/c3ref/last_insert_rowid.html
  """
  @spec last_insert_rowid(db) :: pos_integer
  def last_insert_rowid(db), do: Nif.last_insert_rowid(db)

  # TODO
  @spec transaction_status(db) :: :idle | :transaction
  def transaction_status(db), do: Nif.transaction_status(db)

  @doc """
  Serialize the contents of the database to a binary.

  See: https://sqlite.org/c3ref/serialize.html
  """
  @spec serialize(db, String.t()) :: {:ok, binary} | error
  def serialize(db, schema), do: wrap_error(Nif.dirty_io_serialize(db, schema))

  @doc """
  Disconnect from database and then reopen as an in-memory database based on
  the serialized binary.

  See: https://sqlite.org/c3ref/deserialize.html
  """
  @spec deserialize(db, String.t(), binary) :: :ok | error
  def deserialize(db, schema, serialized) do
    wrap_error(Nif.dirty_io_deserialize(db, schema, serialized))
  end

  @doc """
  Once finished with the prepared statement, call this to release the underlying
  resources.

  This should be called whenever you are done operating with the prepared statement. If
  the system has a high load the garbage collector may not clean up the prepared
  statements in a timely manner and causing higher than normal levels of memory
  pressure.

  If you are operating on limited memory capacity systems, definitely call this.

  See: https://sqlite.org/c3ref/finalize.html
  """
  @spec finalize(stmt) :: :ok | error
  def finalize(stmt), do: wrap_error(Nif.finalize(stmt))

  @doc """
  Allows or disallows loading native extensions.

  See: https://sqlite.org/c3ref/enable_load_extension.html
  """
  @spec enable_load_extension(db, boolean) :: :ok | error
  def enable_load_extension(db, flag) do
    wrap_error(
      case flag do
        true -> Nif.enable_load_extension(db, 1)
        false -> Nif.enable_load_extension(db, 0)
      end
    )
  end

  # TODO
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

  See: https://www.sqlite.org/c3ref/update_hook.html
  """
  @spec set_update_hook(db, pid) :: :ok | error
  def set_update_hook(db, pid), do: wrap_error(Nif.set_update_hook(db, pid))

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

  See: https://sqlite.org/errlog.html
  """
  @spec set_log_hook(pid) :: :ok | error
  def set_log_hook(pid), do: wrap_error(Nif.set_log_hook(pid))

  @doc """
  Executes the prepared statement multiple times. This is a performance optimization.
  """
  @spec multi_step(db, stmt, pos_integer) :: {:rows, [row]} | {:done, [row]} | error
  def multi_step(db, stmt, steps) do
    case Nif.dirty_io_multi_step(db, stmt, steps) do
      # TODO
      {:rows, rows} -> {:rows, Enum.reverse(rows)}
      {:done, rows} -> {:done, Enum.reverse(rows)}
      {:error, _code, _message} = error -> wrap_error(error)
    end
  end

  @doc """
  Fetches all rows from the prepared statement.
  """
  @spec fetch_all(db, stmt, pos_integer) :: {:ok, [row]} | error
  def fetch_all(db, stmt, steps) do
    {:ok, try_fetch_all(db, stmt, steps)}
  catch
    :throw, {:error, _error} = error -> error
  end

  defp try_fetch_all(db, stmt, steps) do
    case multi_step(db, stmt, steps) do
      {:done, rows} -> rows
      # TODO
      {:rows, rows} -> rows ++ try_fetch_all(db, stmt, steps)
      {:error, _error} = error -> throw(error)
    end
  end

  @spec insert_all(db, stmt, [row]) :: :ok | error
  def insert_all(db, stmt, rows),
    do: wrap_error(Nif.dirty_io_insert_all(db, stmt, rows))

  # TODO
  defp wrap_error({:error, code, message}) do
    {:error, Error.exception(code: code, message: message)}
  end

  defp wrap_error(success), do: success
end
