defmodule Exqlite.Nif do
  @moduledoc false

  @compile {:autoload, false}
  @on_load {:load_nif, 0}

  @type usage_error ::
          {:error,
           reason ::
             atom
             | {:wrong_type, term}
             | Keyword.t()}

  @type sqlite_error :: {:error, rc :: integer, msg :: String.t()}
  @type error :: usage_error | sqlite_error

  def load_nif do
    path = :filename.join(:code.priv_dir(:exqlite), ~c"sqlite3_nif")
    :erlang.load_nif(path, 0)
  end

  @spec open(charlist, [Exqlite.open_flag()]) :: {:ok, Exqlite.conn()} | error
  def open(_path, _flags), do: :erlang.nif_error(:not_loaded)

  @spec close(Exqlite.conn()) :: :ok | error
  def close(_conn), do: :erlang.nif_error(:not_loaded)

  @spec execute(Exqlite.conn(), iodata) :: :ok | error
  def execute(_conn, _sql), do: :erlang.nif_error(:not_loaded)

  @spec changes(Exqlite.conn()) :: {:ok, non_neg_integer} | error
  def changes(_conn), do: :erlang.nif_error(:not_loaded)

  @spec prepare(Exqlite.conn(), iodata) :: {:ok, Exqlite.stmt()} | error
  def prepare(_conn, _sql), do: :erlang.nif_error(:not_loaded)

  @spec bind(Exqlite.conn(), Exqlite.stmt(), [Exqlite.bind_arg()]) :: :ok | error
  def bind(_conn, _stmt, _args), do: :erlang.nif_error(:not_loaded)

  @spec step(Exqlite.conn(), Exqlite.stmt()) ::
          {:row, Exqlite.returned_row()} | :done | error
  def step(_conn, _stmt), do: :erlang.nif_error(:not_loaded)

  @spec interrupt(Exqlite.conn()) :: :ok | error
  def interrupt(_conn), do: :erlang.nif_error(:not_loaded)

  @spec multi_step(Exqlite.conn(), Exqlite.stmt(), non_neg_integer) ::
          {:rows | :done, [Exqlite.returned_row()]} | error
  def multi_step(_conn, _stmt, _max_rows), do: :erlang.nif_error(:not_loaded)

  @spec columns(Exqlite.conn(), Exqlite.stmt()) :: {:ok, [String.t()]} | error
  def columns(_conn, _stmt), do: :erlang.nif_error(:not_loaded)

  @spec last_insert_rowid(Exqlite.conn()) :: {:ok, non_neg_integer} | error
  def last_insert_rowid(_conn), do: :erlang.nif_error(:not_loaded)

  @spec transaction_status(Exqlite.conn()) ::
          {:ok, :transaction | :idle} | error
  def transaction_status(_conn), do: :erlang.nif_error(:not_loaded)

  @spec serialize(Exqlite.conn(), charlist) :: {:ok, binary} | error
  def serialize(_conn, _database), do: :erlang.nif_error(:not_loaded)

  @spec deserialize(Exqlite.conn(), charlist, iodata) :: :ok | error
  def deserialize(_conn, _database, _serialized), do: :erlang.nif_error(:not_loaded)

  @spec release(Exqlite.stmt()) :: :ok | error
  def release(_stmt), do: :erlang.nif_error(:not_loaded)

  @spec enable_load_extension(Exqlite.conn(), integer) :: :ok | error
  def enable_load_extension(_conn, _flag), do: :erlang.nif_error(:not_loaded)

  @spec set_update_hook(Exqlite.conn(), pid) :: :ok | error
  def set_update_hook(_conn, _pid), do: :erlang.nif_error(:not_loaded)

  @spec set_log_hook(pid) :: :ok | error
  def set_log_hook(_pid), do: :erlang.nif_error(:not_loaded)

  @spec error_info(Exqlite.conn()) :: %{
          errcode: integer,
          extended_errcode: integer,
          errstr: String.t(),
          errmsg: String.t(),
          error_offset: integer
        }
  def error_info(_conn), do: :erlang.nif_error(:not_loaded)
end
