defmodule Exqlite.RWConnection do
  @moduledoc """
  Connections are modelled as processes.
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

  def stop(conn) do
    GenServer.stop(conn)
  end

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

    with {:ok, db} <- Sqlite3.open(database, options),
         :ok <- Sqlite3.execute(db, "pragma journal_mode=wal"),
         :ok <- Sqlite3.execute(db, "pragma foreign_keys=on") do
      state = %{db: db, lock: :none, queue: :queue.new(), reads: %{}}
      {:ok, state}
    else
      {:error, reason} ->
        {:error, error_to_exception(reason)}
    end
  end

  defp error_to_exception(reason) do
    Exqlite.Error.exception(message: to_string(reason))
  end

  @impl true
  def handle_call({:read, command}, from, %{lock: :none} = state) do
    case handle_command(command, state.db) do
      {:ok, statement_ref} ->
        {pid, _} = from
        unregister_ref = Process.monitor(pid)
        reply = {:ok, state.db, unregister_ref, statement_ref}
        state = %{state | reads: Map.put(state.reads, unregister_ref, statement_ref)}
        {:reply, reply, state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:lock, command}, from, state) do
    state = update_in(state.queue, &:queue.in({:lock, command, from}, &1))

    if map_size(state.reads) > 0 do
      {:noreply, %{state | lock: :drain}}
    else
      {:noreply, maybe_dequeue(state)}
    end
  end

  def handle_call({:read, command}, from, state) do
    state = update_in(state.queue, &:queue.in({:read, command, from}, &1))
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
    :ok = Sqlite3.release(state.db, statement_ref)
    maybe_dequeue(%{state | lock: :none})
  end

  defp unregister(state, ref) do
    {statement_ref, reads} = Map.pop!(state.reads, ref)
    if statement_ref, do: :ok = Sqlite3.release(state.db, statement_ref)
    state = %{state | reads: reads}

    if state.lock == :drain and map_size(reads) == 0 do
      maybe_dequeue(%{state | lock: :none})
    else
      state
    end
  end

  defp maybe_dequeue(%{lock: :none, queue: queue} = state) do
    case :queue.out(queue) do
      {:empty, queue} ->
        %{state | queue: queue}

      {{:value, value}, queue} ->
        case value do
          {:lock, command, from} ->
            {pid, _} = from

            case handle_command(command, state.db) do
              {:ok, statement_ref} when is_reference(statement_ref) ->
                unlock_ref = Process.monitor(pid)
                GenServer.reply(from, {:ok, state.db, unlock_ref, statement_ref})
                %{state | lock: {unlock_ref, statement_ref}, queue: queue}

              {:error, _reason} = error ->
                GenServer.reply(from, error)
                maybe_dequeue(%{state | queue: queue})
            end

          {:read, command, from} ->
            {pid, _} = from

            case handle_command(command, state.db) do
              {:ok, statement_ref} when is_reference(statement_ref) ->
                unregister_ref = Process.monitor(pid)
                GenServer.reply(from, {:ok, state.db, unregister_ref, statement_ref})

                %{
                  state
                  | reads: Map.put(state.reads, unregister_ref, statement_ref),
                    queue: queue
                }

              {:error, _reason} = error ->
                GenServer.reply(from, error)
                maybe_dequeue(%{state | queue: queue})
            end
        end
    end
  end

  defp maybe_dequeue(state), do: state

  defp handle_command({:query, query, params}, db) do
    with {:ok, stmt} = ok <- Sqlite3.prepare(db, query),
         :ok <- maybe_bind(db, stmt, params),
         do: ok
  end

  defp maybe_bind(_db, _stmt, []), do: :ok
  defp maybe_bind(db, stmt, params), do: Sqlite3.bind(db, stmt, params)
end
