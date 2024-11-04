defmodule Exqlite.Connection do
  @moduledoc """
  This module implements connection details as defined in DBProtocol.

  ## Attributes

  - `db` - The sqlite3 database reference.
  - `path` - The path that was used to open.
  - `transaction_status` - The status of the connection. Can be `:idle` or `:transaction`.

  ## Unknowns

  - How are pooled connections going to work? Since sqlite3 doesn't allow for
    simultaneous access. We would need to check if the write ahead log is
    enabled on the database. We can't assume and set the WAL pragma because the
    database may be stored on a network volume which would cause potential
    issues.

  Notes:
    - we try to closely follow structure and naming convention of myxql.
    - sqlite thrives when there are many small conventions, so we may not implement
      some strategies employed by other adapters. See https://sqlite.org/np1queryprob.html
  """

  use DBConnection
  alias Exqlite.Error
  alias Exqlite.Pragma
  alias Exqlite.Query
  alias Exqlite.Result
  alias Exqlite.Sqlite3
  require Logger

  defstruct [
    :db,
    :default_transaction_mode,
    :directory,
    :path,
    :transaction_status,
    :status,
    :chunk_size,
    :before_disconnect
  ]

  @type t() :: %__MODULE__{
          db: Sqlite3.db(),
          directory: String.t() | nil,
          path: String.t(),
          transaction_status: :idle | :transaction,
          status: :idle | :busy,
          chunk_size: integer(),
          before_disconnect: (t -> any) | {module, atom, [any]} | nil
        }

  @type journal_mode() :: :delete | :truncate | :persist | :memory | :wal | :off
  @type temp_store() :: :default | :file | :memory
  @type synchronous() :: :extra | :full | :normal | :off
  @type auto_vacuum() :: :none | :full | :incremental
  @type locking_mode() :: :normal | :exclusive
  @type transaction_mode() :: :deferred | :immediate | :exclusive

  @type connection_opt() ::
          {:database, String.t()}
          | {:default_transaction_mode, transaction_mode()}
          | {:mode, Sqlite3.open_opt()}
          | {:journal_mode, journal_mode()}
          | {:temp_store, temp_store()}
          | {:synchronous, synchronous()}
          | {:foreign_keys, :on | :off}
          | {:cache_size, integer()}
          | {:cache_spill, :on | :off}
          | {:case_sensitive_like, boolean()}
          | {:auto_vacuum, auto_vacuum()}
          | {:locking_mode, locking_mode()}
          | {:secure_delete, :on | :off}
          | {:wal_auto_check_point, integer()}
          | {:busy_timeout, integer()}
          | {:chunk_size, integer()}
          | {:journal_size_limit, integer()}
          | {:soft_heap_limit, integer()}
          | {:hard_heap_limit, integer()}
          | {:key, String.t()}
          | {:custom_pragmas, [{keyword(), integer() | boolean() | String.t()}]}
          | {:before_disconnect, (t -> any) | {module, atom, [any]} | nil}

  @impl true
  @doc """
  Initializes the Ecto Exqlite adapter.

  For connection configurations we use the defaults that come with SQLite3, but
  we recommend which options to choose. We do not default to the recommended
  because we don't know what your environment is like.

  Allowed options:

    * `:database` - The path to the database. In memory is allowed. You can use
      `:memory` or `":memory:"` to designate that.
    * `:default_transaction_mode` - one of `deferred` (default), `immediate`,
      or `exclusive`. If a mode is not specified in a call to `Repo.transaction/2`,
      this will be the default transaction mode.
    * `:mode` - use `:readwrite` to open the database for reading and writing
      , `:readonly` to open it in read-only mode or `[:readonly | :readwrite, :nomutex]`
      to open it with no mutex mode. `:readwrite` will also create
      the database if it doesn't already exist. Defaults to `:readwrite`.
      Note: [:readwrite, :nomutex] is not recommended.
    * `:journal_mode` - Sets the journal mode for the sqlite connection. Can be
      one of the following `:delete`, `:truncate`, `:persist`, `:memory`,
      `:wal`, or `:off`. Defaults to `:delete`. It is recommended that you use
      `:wal` due to support for concurrent reads. Note: `:wal` does not mean
      concurrent writes.
    * `:temp_store` - Sets the storage used for temporary tables. Default is
      `:default`. Allowed values are `:default`, `:file`, `:memory`. It is
      recommended that you use `:memory` for storage.
    * `:synchronous` - Can be `:extra`, `:full`, `:normal`, or `:off`. Defaults
      to `:normal`.
    * `:foreign_keys` - Sets if foreign key checks should be enforced or not.
      Can be `:on` or `:off`. Default is `:on`.
    * `:cache_size` - Sets the cache size to be used for the connection. This is
      an odd setting as a positive value is the number of pages in memory to use
      and a negative value is the size in kilobytes to use. Default is `-2000`.
      It is recommended that you use `-64000`.
    * `:cache_spill` - The cache_spill pragma enables or disables the ability of
      the pager to spill dirty cache pages to the database file in the middle of
      a transaction. By default it is `:on`, and for most applications, it
      should remain so.
    * `:case_sensitive_like`
    * `:auto_vacuum` - Defaults to `:none`. Can be `:none`, `:full` or
      `:incremental`. Depending on the database size, `:incremental` may be
      beneficial.
    * `:locking_mode` - Defaults to `:normal`. Allowed values are `:normal` or
      `:exclusive`. See [sqlite documentation][1] for more information.
    * `:secure_delete` - Defaults to `:off`. If enabled, it will cause SQLite3
      to overwrite records that were deleted with zeros.
    * `:wal_auto_check_point` - Sets the write-ahead log auto-checkpoint
      interval. Default is `1000`. Setting the auto-checkpoint size to zero or a
      negative value turns auto-checkpointing off.
    * `:busy_timeout` - Sets the busy timeout in milliseconds for a connection.
      Default is `2000`.
    * `:chunk_size` - The chunk size for bulk fetching. Defaults to `50`.
    * `:key` - Optional key to set during database initialization. This PRAGMA
      is often used to set up database level encryption.
    * `:journal_size_limit` - The size limit in bytes of the journal.
    * `:soft_heap_limit` - The size limit in bytes for the heap limit.
    * `:hard_heap_limit` - The size limit in bytes for the heap.
    * `:custom_pragmas` - A list of custom pragmas to set on the connection, for example to configure extensions.
    * `:load_extensions` - A list of paths identifying extensions to load. Defaults to `[]`.
      The provided list will be merged with the global extensions list, set on `:exqlite, :load_extensions`.
      Be aware that the path should handle pointing to a library compiled for the current architecture.
      Example configuration:

      ```
        arch_dir =
          System.cmd("uname", ["-sm"])
          |> elem(0)
          |> String.trim()
          |> String.replace(" ", "-")
          |> String.downcase() # => "darwin-arm64"

        config :myapp, arch_dir: arch_dir

        # global
        config :exqlite, load_extensions: [ "./priv/sqlite/\#{arch_dir}/rotate" ]

        # per connection in a Phoenix app
        config :myapp, Myapp.Repo,
          database: "path/to/db",
          load_extensions: [
            "./priv/sqlite/\#{arch_dir}/vector0",
            "./priv/sqlite/\#{arch_dir}/vss0"
          ]
      ```
    * `:before_disconnect` - A function to run before disconnect, either a
      2-arity fun or `{module, function, args}` with the close reason and
      `t:Exqlite.Connection.t/0` prepended to `args` or `nil` (default: `nil`)

  For more information about the options above, see [sqlite documentation][1]

  [1]: https://www.sqlite.org/pragma.html
  """
  @spec connect([connection_opt()]) :: {:ok, t()} | {:error, Exception.t()}
  def connect(options) do
    database = Keyword.get(options, :database)

    options =
      Keyword.put_new(
        options,
        :chunk_size,
        Application.get_env(:exqlite, :default_chunk_size, 50)
      )

    case database do
      nil ->
        {:error,
         %Error{
           message: """
           You must provide a :database to the database. \
           Example: connect(database: "./") or connect(database: :memory)\
           """
         }}

      :memory ->
        do_connect(":memory:", options)

      _ ->
        do_connect(database, options)
    end
  end

  @impl true
  def disconnect(err, %__MODULE__{db: db} = state) do
    if state.before_disconnect != nil do
      apply(state.before_disconnect, [err, state])
    end

    case Sqlite3.close(db) do
      :ok -> :ok
      {:error, reason} -> {:error, %Error{message: to_string(reason)}}
    end
  end

  @impl true
  def checkout(%__MODULE__{status: :idle} = state) do
    {:ok, %{state | status: :busy}}
  end

  def checkout(%__MODULE__{status: :busy} = state) do
    {:disconnect, %Error{message: "Database is busy"}, state}
  end

  @impl true
  def ping(state), do: {:ok, state}

  ##
  ## Handlers
  ##

  @impl true
  def handle_prepare(%Query{} = query, options, state) do
    with {:ok, query} <- prepare(query, options, state) do
      {:ok, query, state}
    end
  end

  @impl true
  def handle_execute(%Query{} = query, params, options, state) do
    with {:ok, query} <- prepare(query, options, state) do
      execute(:execute, query, params, state)
    end
  end

  @doc """
  Begin a transaction.

  For full info refer to sqlite docs: https://sqlite.org/lang_transaction.html

  Note: default transaction mode is DEFERRED.
  """
  @impl true
  def handle_begin(options, %{transaction_status: transaction_status} = state) do
    # This doesn't handle more than 2 levels of transactions.
    #
    # One possible solution would be to just track the number of open
    # transactions and use that for driving the transaction status being idle or
    # in a transaction.
    #
    # I do not know why the other official adapters do not track this and just
    # append level on the savepoint. Instead the rollbacks would just completely
    # revert the issues when it may be desirable to fix something while in the
    # transaction and then commit.

    mode = Keyword.get(options, :mode, state.default_transaction_mode)

    case mode do
      :deferred when transaction_status == :idle ->
        handle_transaction(:begin, "BEGIN TRANSACTION", state)

      :transaction when transaction_status == :idle ->
        handle_transaction(:begin, "BEGIN TRANSACTION", state)

      :immediate when transaction_status == :idle ->
        handle_transaction(:begin, "BEGIN IMMEDIATE TRANSACTION", state)

      :exclusive when transaction_status == :idle ->
        handle_transaction(:begin, "BEGIN EXCLUSIVE TRANSACTION", state)

      mode
      when mode in [:deferred, :immediate, :exclusive, :savepoint] and
             transaction_status == :transaction ->
        handle_transaction(:begin, "SAVEPOINT exqlite_savepoint", state)
    end
  end

  @impl true
  def handle_commit(options, %{transaction_status: transaction_status} = state) do
    case Keyword.get(options, :mode, :deferred) do
      :savepoint when transaction_status == :transaction ->
        handle_transaction(
          :commit_savepoint,
          "RELEASE SAVEPOINT exqlite_savepoint",
          state
        )

      mode
      when mode in [:deferred, :immediate, :exclusive, :transaction] and
             transaction_status == :transaction ->
        handle_transaction(:commit, "COMMIT", state)
    end
  end

  @impl true
  def handle_rollback(options, %{transaction_status: transaction_status} = state) do
    case Keyword.get(options, :mode, :deferred) do
      :savepoint when transaction_status == :transaction ->
        with {:ok, _result, state} <-
               handle_transaction(
                 :rollback_savepoint,
                 "ROLLBACK TO SAVEPOINT exqlite_savepoint",
                 state
               ) do
          handle_transaction(
            :rollback_savepoint,
            "RELEASE SAVEPOINT exqlite_savepoint",
            state
          )
        end

      mode
      when mode in [:deferred, :immediate, :exclusive, :transaction] ->
        handle_transaction(:rollback, "ROLLBACK TRANSACTION", state)
    end
  end

  @doc """
  Close a query prepared by `handle_prepare/3` with the database. Return
  `{:ok, result, state}` on success and to continue,
  `{:error, exception, state}` to return an error and continue, or
  `{:disconnect, exception, state}` to return an error and disconnect.

  This callback is called in the client process.
  """
  @impl true
  def handle_close(query, _opts, state) do
    Sqlite3.release(state.db, query.ref)
    {:ok, nil, state}
  end

  @impl true
  def handle_declare(%Query{} = query, params, opts, state) do
    # We emulate cursor functionality by just using a prepared statement and
    # step through it. Thus we just return the query ref as the cursor.
    with {:ok, query} <- prepare_no_cache(query, opts, state),
         {:ok, query} <- bind_params(query, params, state) do
      {:ok, query, query.ref, state}
    end
  end

  @impl true
  def handle_deallocate(%Query{} = query, _cursor, _opts, state) do
    Sqlite3.release(state.db, query.ref)
    {:ok, nil, state}
  end

  @impl true
  def handle_fetch(%Query{statement: statement}, cursor, opts, state) do
    chunk_size = opts[:chunk_size] || opts[:max_rows] || state.chunk_size

    case Sqlite3.multi_step(state.db, cursor, chunk_size) do
      {:done, rows} ->
        {:halt, %Result{rows: rows, command: :fetch, num_rows: length(rows)}, state}

      {:rows, rows} ->
        {:cont, %Result{rows: rows, command: :fetch, num_rows: chunk_size}, state}

      {:error, reason} ->
        {:error, %Error{message: to_string(reason), statement: statement}, state}

      :busy ->
        {:error, %Error{message: "Database is busy", statement: statement}, state}
    end
  end

  @impl true
  def handle_status(_opts, state) do
    {state.transaction_status, state}
  end

  ### ----------------------------------
  #     Internal functions and helpers
  ### ----------------------------------

  defp set_pragma(db, pragma_name, value) do
    Sqlite3.execute(db, "PRAGMA #{pragma_name} = #{value}")
  end

  defp get_pragma(db, pragma_name) do
    {:ok, statement} = Sqlite3.prepare(db, "PRAGMA #{pragma_name}")

    case Sqlite3.fetch_all(db, statement) do
      {:ok, [[value]]} -> {:ok, value}
      _ -> :error
    end
  end

  defp maybe_set_pragma(db, pragma_name, value) do
    case get_pragma(db, pragma_name) do
      {:ok, current} ->
        if current == value do
          :ok
        else
          set_pragma(db, pragma_name, value)
        end

      _ ->
        set_pragma(db, pragma_name, value)
    end
  end

  defp set_key(db, options) do
    # we can't use maybe_set_pragma here since
    # the only thing that will work on an encrypted
    # database without error is setting the key.
    case Keyword.fetch(options, :key) do
      {:ok, key} -> set_pragma(db, "key", key)
      _ -> :ok
    end
  end

  defp set_custom_pragmas(db, options) do
    # we can't use maybe_set_pragma because some pragmas
    # are required to be set before the database is e.g. decrypted.
    case Keyword.fetch(options, :custom_pragmas) do
      {:ok, list} -> do_set_custom_pragmas(db, list)
      _ -> :ok
    end
  end

  defp do_set_custom_pragmas(db, list) do
    list
    |> Enum.reduce_while(:ok, fn {key, value}, :ok ->
      case set_pragma(db, key, value) do
        :ok -> {:cont, :ok}
        {:error, _reason} -> {:halt, :error}
      end
    end)
  end

  defp set_pragma_if_present(_db, _pragma, nil), do: :ok
  defp set_pragma_if_present(db, pragma, value), do: set_pragma(db, pragma, value)

  defp set_journal_size_limit(db, options) do
    set_pragma_if_present(
      db,
      "journal_size_limit",
      Keyword.get(options, :journal_size_limit)
    )
  end

  defp set_soft_heap_limit(db, options) do
    set_pragma_if_present(db, "soft_heap_limit", Keyword.get(options, :soft_heap_limit))
  end

  defp set_hard_heap_limit(db, options) do
    set_pragma_if_present(db, "hard_heap_limit", Keyword.get(options, :hard_heap_limit))
  end

  defp set_journal_mode(db, options) do
    maybe_set_pragma(db, "journal_mode", Pragma.journal_mode(options))
  end

  defp set_temp_store(db, options) do
    set_pragma(db, "temp_store", Pragma.temp_store(options))
  end

  defp set_synchronous(db, options) do
    set_pragma(db, "synchronous", Pragma.synchronous(options))
  end

  defp set_foreign_keys(db, options) do
    set_pragma(db, "foreign_keys", Pragma.foreign_keys(options))
  end

  defp set_cache_size(db, options) do
    maybe_set_pragma(db, "cache_size", Pragma.cache_size(options))
  end

  defp set_cache_spill(db, options) do
    set_pragma(db, "cache_spill", Pragma.cache_spill(options))
  end

  defp set_case_sensitive_like(db, options) do
    set_pragma(db, "case_sensitive_like", Pragma.case_sensitive_like(options))
  end

  defp set_auto_vacuum(db, options) do
    set_pragma(db, "auto_vacuum", Pragma.auto_vacuum(options))
  end

  defp set_locking_mode(db, options) do
    set_pragma(db, "locking_mode", Pragma.locking_mode(options))
  end

  defp set_secure_delete(db, options) do
    set_pragma(db, "secure_delete", Pragma.secure_delete(options))
  end

  defp set_wal_auto_check_point(db, options) do
    set_pragma(db, "wal_autocheckpoint", Pragma.wal_auto_check_point(options))
  end

  defp set_busy_timeout(db, options) do
    set_pragma(db, "busy_timeout", Pragma.busy_timeout(options))
  end

  defp load_extensions(db, options) do
    global_extensions = Application.get_env(:exqlite, :load_extensions, [])

    extensions =
      Keyword.get(options, :load_extensions, [])
      |> Enum.concat(global_extensions)
      |> Enum.uniq()

    do_load_extensions(db, extensions)
  end

  defp do_load_extensions(_db, []), do: :ok

  defp do_load_extensions(db, extensions) do
    Sqlite3.enable_load_extension(db, true)

    Enum.each(extensions, fn extension ->
      Logger.debug(fn -> "Exqlite: loading extension `#{extension}`" end)
      Sqlite3.execute(db, "SELECT load_extension('#{extension}')")
    end)

    Sqlite3.enable_load_extension(db, false)
  end

  defp do_connect(database, options) do
    with {:ok, directory} <- resolve_directory(database),
         :ok <- mkdir_p(directory),
         {:ok, db} <- Sqlite3.open(database, options),
         :ok <- set_key(db, options),
         :ok <- set_custom_pragmas(db, options),
         :ok <- set_journal_mode(db, options),
         :ok <- set_temp_store(db, options),
         :ok <- set_synchronous(db, options),
         :ok <- set_foreign_keys(db, options),
         :ok <- set_cache_size(db, options),
         :ok <- set_cache_spill(db, options),
         :ok <- set_auto_vacuum(db, options),
         :ok <- set_locking_mode(db, options),
         :ok <- set_secure_delete(db, options),
         :ok <- set_wal_auto_check_point(db, options),
         :ok <- set_case_sensitive_like(db, options),
         :ok <- set_busy_timeout(db, options),
         :ok <- set_journal_size_limit(db, options),
         :ok <- set_soft_heap_limit(db, options),
         :ok <- set_hard_heap_limit(db, options),
         :ok <- load_extensions(db, options) do
      state = %__MODULE__{
        db: db,
        default_transaction_mode:
          Keyword.get(options, :default_transaction_mode, :deferred),
        directory: directory,
        path: database,
        transaction_status: :idle,
        status: :idle,
        chunk_size: Keyword.get(options, :chunk_size),
        before_disconnect: Keyword.get(options, :before_disconnect, nil)
      }

      {:ok, state}
    else
      {:error, reason} ->
        {:error, %Exqlite.Error{message: to_string(reason)}}
    end
  end

  def maybe_put_command(query, options) do
    case Keyword.get(options, :command) do
      nil -> query
      command -> %{query | command: command}
    end
  end

  # Attempt to retrieve the cached query, if it doesn't exist, we'll prepare one
  # and cache it for later.
  defp prepare(%Query{statement: statement} = query, options, state) do
    query = maybe_put_command(query, options)

    with {:ok, ref} <- Sqlite3.prepare(state.db, IO.iodata_to_binary(statement)),
         query <- %{query | ref: ref} do
      {:ok, query}
    else
      {:error, reason} ->
        {:error, %Error{message: to_string(reason), statement: statement}, state}
    end
  end

  # Prepare a query and do not cache it.
  defp prepare_no_cache(%Query{statement: statement} = query, options, state) do
    query = maybe_put_command(query, options)

    case Sqlite3.prepare(state.db, statement) do
      {:ok, ref} ->
        {:ok, %{query | ref: ref}}

      {:error, reason} ->
        {:error, %Error{message: to_string(reason), statement: statement}, state}
    end
  end

  @spec maybe_changes(Sqlite3.db(), Query.t()) :: integer() | nil
  defp maybe_changes(db, %Query{command: command})
       when command in [:update, :insert, :delete] do
    case Sqlite3.changes(db) do
      {:ok, total} -> total
      _ -> nil
    end
  end

  defp maybe_changes(_, _), do: nil

  # when we have an empty list of columns, that signifies that
  # there was no possible return tuple (e.g., update statement without RETURNING)
  # and in that case, we return nil to signify no possible result.
  defp maybe_rows([], []), do: nil
  defp maybe_rows(rows, _cols), do: rows

  defp execute(call, %Query{} = query, params, state) do
    with {:ok, query} <- bind_params(query, params, state),
         {:ok, columns} <- get_columns(query, state),
         {:ok, rows} <- get_rows(query, state),
         {:ok, transaction_status} <- Sqlite3.transaction_status(state.db),
         changes <- maybe_changes(state.db, query) do
      case query.command do
        command when command in [:delete, :insert, :update] ->
          {
            :ok,
            query,
            Result.new(
              command: call,
              num_rows: changes,
              rows: maybe_rows(rows, columns)
            ),
            %{state | transaction_status: transaction_status}
          }

        _ ->
          {
            :ok,
            query,
            Result.new(
              command: call,
              columns: columns,
              rows: rows,
              num_rows: Enum.count(rows)
            ),
            %{state | transaction_status: transaction_status}
          }
      end
    end
  end

  defp bind_params(%Query{ref: ref, statement: statement} = query, params, state)
       when ref != nil do
    try do
      Sqlite3.bind(ref, params)
    rescue
      e -> {:error, %Error{message: Exception.message(e), statement: statement}, state}
    else
      :ok -> {:ok, query}
    end
  end

  defp get_columns(%Query{ref: ref, statement: statement}, state) do
    case Sqlite3.columns(state.db, ref) do
      {:ok, columns} ->
        {:ok, columns}

      {:error, reason} ->
        {:error, %Error{message: to_string(reason), statement: statement}, state}
    end
  end

  defp get_rows(%Query{ref: ref, statement: statement}, state) do
    case Sqlite3.fetch_all(state.db, ref, state.chunk_size) do
      {:ok, rows} ->
        {:ok, rows}

      {:error, reason} ->
        {:error, %Error{message: to_string(reason), statement: statement}, state}
    end
  end

  defp handle_transaction(call, statement, state) do
    with :ok <- Sqlite3.execute(state.db, statement),
         {:ok, transaction_status} <- Sqlite3.transaction_status(state.db) do
      result = %Result{
        command: call,
        rows: [],
        columns: [],
        num_rows: 0
      }

      {:ok, result, %{state | transaction_status: transaction_status}}
    else
      {:error, reason} ->
        {:disconnect, %Error{message: to_string(reason), statement: statement}, state}
    end
  end

  defp resolve_directory(":memory:"), do: {:ok, nil}

  defp resolve_directory("file:" <> _ = uri) do
    case URI.parse(uri) do
      %{path: path} when is_binary(path) ->
        {:ok, Path.dirname(path)}

      _ ->
        {:error, "No path in #{inspect(uri)}"}
    end
  end

  defp resolve_directory(path), do: {:ok, Path.dirname(path)}

  # SQLITE_OPEN_CREATE will create the DB file if not existing, but
  # will not create intermediary directories if they are missing.
  # So let's preemptively create the intermediate directories here
  # before trying to open the DB file.
  defp mkdir_p(nil), do: :ok
  defp mkdir_p(directory), do: File.mkdir_p(directory)
end
