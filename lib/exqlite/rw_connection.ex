defmodule Exqlite.RWConnection do
  @moduledoc """
  RWConnection owns two SQLite3 open databases. One is used for serialized writes and the other is used for concurrent reads.
  When a write finishes, the "reads" database is drained of statements to get out of implicit transaction and see new data.
  """

  use GenServer
  alias Exqlite.Sqlite3

  @type t :: GenServer.server()

  @doc """
  Starts a connection process.

  ## Options

    * `:database` (required) - the database process to connect to

    * `:process_options` - the options to be given to the underlying
      process. See `GenServer.start_link/3` for all options

  ## Examples

      #{__MODULE__}.start_link(
        database: ":memory:",
        process_options: [name: MyApp.Conn]
      )

  In your supervision tree it would be started like this:

      children = [
        {#{__MODULE__},
         database: ":memory:",
         process_options: [name: MyApp.Conn]}
      ]

  """
  def start_link(options) do
    {process_options, options} = Keyword.pop(options, :process_options, [])
    GenServer.start_link(__MODULE__, options, process_options)
  end

  def stop(conn), do: GenServer.stop(conn)

  @doc """
  Runs the given `query` with `params` while exclusively locking the connection.

  ## Examples

      query(MyApp.Conn, "create table users(name)")
      query(conn, "insert into users(names) values (?), (?)", ["bim", "bom"])

  """
  def query(conn, query, params \\ []) do
    command(conn, :lock, {:query, query, params}, &result/2)
  end

  @doc """
  Runs the given `query` with `params` without locking the connection.
  Should only be used for reading.

  ## Examples

      read_query(MyApp.Conn, "select * from users")
      read_query(conn, "select * from users where name = ?", ["bimbom"])

  """
  def read_query(conn, query, params \\ []) do
    command(conn, :read, {:query, query, params}, &result/2)
  end

  defp command(conn, type, command, fun) do
    case GenServer.call(conn, {type, command}, :infinity) do
      {:ok, db, undo_ref, statement_ref} ->
        try do
          fun.(db, statement_ref)
        after
          GenServer.cast(conn, {:undo, type, undo_ref})
        end

      {:error, reason} ->
        {:error, error_to_exception(reason)}
    end
  end

  defp result(db, statement_ref) do
    with {:ok, columns} <- Sqlite3.columns(db, statement_ref),
         {:ok, rows} <- Sqlite3.fetch_all(db, statement_ref, _chunk_size = 100),
         do: {:ok, %Exqlite.Result{columns: columns, rows: rows}}
  end

  @impl true
  def init(options) do
    database = Keyword.fetch!(options, :database)

    if database in [:memory, ":memory:"] do
      raise "#{database} is not supported in #{__MODULE__}"
    end

    open_result =
      if options[:mode] == :readonly do
        with {:ok, db} <- open_and_configure(database, options), do: {:ok, db, db}
      else
        read_options = Keyword.put(options, :mode, :readonly)

        with {:ok, write_db} <- open_and_configure(database, options),
             {:ok, read_db} <- open_and_configure(database, read_options),
             do: {:ok, write_db, read_db}
      end

    with {:ok, write_db, read_db} <- open_result do
      state = %{
        write_db: write_db,
        read_db: read_db,
        lock: :none,
        readable: true,
        write_queue: :queue.new(),
        read_queue: :queue.new(),
        reads: %{}
      }

      {:ok, state}
    else
      {:error, reason} ->
        {:error, error_to_exception(reason)}
    end
  end

  defp open_and_configure(database, options) do
    with {:ok, ref} = ok <- Sqlite3.open(database, options),
         :ok <- Sqlite3.execute(ref, "pragma journal_mode=wal"),
         :ok <- Sqlite3.execute(ref, "pragma foreign_keys=on"),
         do: ok
  end

  defp error_to_exception(reason) do
    Exqlite.Error.exception(message: to_string(reason))
  end

  @impl true
  def handle_call({:read, command}, from, %{readable: true} = state) do
    %{read_db: read_db, reads: reads} = state

    case handle_command(command, read_db) do
      {:ok, statement_ref} ->
        {pid, _} = from
        unregister_ref = Process.monitor(pid)
        reply = {:ok, read_db, unregister_ref, statement_ref}
        state = %{state | reads: Map.put(reads, unregister_ref, statement_ref)}
        {:reply, reply, state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:lock, command}, from, state) do
    state = update_in(state.write_queue, &:queue.in({:lock, command, from}, &1))
    {:noreply, maybe_dequeue(state)}
  end

  def handle_call({:read, command}, from, state) do
    state = update_in(state.read_queue, &:queue.in({:read, command, from}, &1))
    {:noreply, state}
  end

  @impl true
  def handle_cast({:undo, :lock, ref}, %{lock: {ref, statement_ref}} = state) do
    Process.demonitor(ref, [:flush])
    {:noreply, unlock(state, statement_ref)}
  end

  def handle_cast({:undo, :read, ref}, state) do
    Process.demonitor(ref, [:flush])
    {:noreply, unregister(state, ref)}
  end

  @impl true
  def handle_info({:DOWN, ref, _, _, _}, %{lock: {ref, statement_ref}} = state) do
    {:noreply, unlock(state, statement_ref)}
  end

  def handle_info({:DOWN, ref, _, _, _}, state) do
    {:noreply, unregister(state, ref)}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp unlock(state, statement_ref) do
    %{write_db: write_db, reads: reads} = state
    :ok = Sqlite3.release(write_db, statement_ref)

    state =
      if map_size(reads) > 0 do
        %{state | readable: false}
      else
        state
      end

    maybe_dequeue(%{state | lock: :none})
  end

  defp unregister(state, ref) do
    %{read_db: read_db, reads: reads} = state

    {statement_ref, reads} = Map.pop!(reads, ref)
    if statement_ref, do: :ok = Sqlite3.release(read_db, statement_ref)
    state = %{state | reads: reads}

    if not state.readable and map_size(reads) == 0 do
      restart_reads(%{state | readable: true})
    else
      state
    end
  end

  defp maybe_dequeue(%{lock: :none} = state) do
    case :queue.out(state.write_queue) do
      {:empty, write_queue} ->
        %{state | write_queue: write_queue}

      {{:value, {:lock, command, from}}, write_queue} ->
        {pid, _} = from
        %{write_db: write_db} = state

        case handle_command(command, write_db) do
          {:ok, statement_ref} when is_reference(statement_ref) ->
            unlock_ref = Process.monitor(pid)
            GenServer.reply(from, {:ok, write_db, unlock_ref, statement_ref})
            %{state | lock: {unlock_ref, statement_ref}, write_queue: write_queue}

          {:error, _reason} = error ->
            GenServer.reply(from, error)
            maybe_dequeue(%{state | write_queue: write_queue})
        end
    end
  end

  defp maybe_dequeue(state), do: state

  defp restart_reads(state) do
    case :queue.out(state.read_queue) do
      {:empty, read_queue} ->
        %{state | read_queue: read_queue}

      {{:value, {:read, command, from}}, read_queue} ->
        {pid, _} = from
        %{read_db: read_db, reads: reads} = state

        state =
          case handle_command(command, read_db) do
            {:ok, statement_ref} when is_reference(statement_ref) ->
              unregister_ref = Process.monitor(pid)
              GenServer.reply(from, {:ok, read_db, unregister_ref, statement_ref})
              %{state | reads: Map.put(reads, unregister_ref, statement_ref)}

            {:error, _reason} = error ->
              GenServer.reply(from, error)
              state
          end

        restart_reads(%{state | read_queue: read_queue})
    end
  end

  defp handle_command({:query, query, params}, db) do
    with {:ok, stmt} = ok <- Sqlite3.prepare(db, query),
         :ok <- maybe_bind(db, stmt, params),
         do: ok
  end

  defp maybe_bind(_db, _stmt, []), do: :ok
  defp maybe_bind(db, stmt, params), do: Sqlite3.bind(db, stmt, params)
end
