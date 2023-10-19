defmodule Exqlite.Sqlite3NIF do
  @moduledoc """
  This is the module where all of the NIF entry points reside. Calling this directly
  should be avoided unless you are aware of what you are doing.
  """

  @compile {:autoload, false}
  @on_load {:load_nif, 0}

  @type db() :: reference()
  @type statement() :: reference()
  @type reason() :: :atom | String.Chars.t()
  @type row() :: list()

  def load_nif() do
    path = :filename.join(:code.priv_dir(:exqlite), ~c"sqlite3_nif")
    :erlang.load_nif(path, 0)
  end

  @spec open(String.Chars.t(), integer()) :: {:ok, db()} | {:error, reason()}
  def open(_path, _flags), do: :erlang.nif_error(:not_loaded)

  @spec close(db()) :: :ok | {:error, reason()}
  def close(_conn), do: :erlang.nif_error(:not_loaded)

  @spec execute(db(), String.Chars.t()) :: :ok | {:error, reason()}
  def execute(_conn, _sql), do: :erlang.nif_error(:not_loaded)

  @spec changes(db()) :: {:ok, integer()} | {:error, reason()}
  def changes(_conn), do: :erlang.nif_error(:not_loaded)

  @spec prepare(db(), String.Chars.t()) :: {:ok, statement()} | {:error, reason()}
  def prepare(_conn, _sql), do: :erlang.nif_error(:not_loaded)

  @spec bind(db(), statement(), list()) ::
          :ok | {:error, reason()} | {:error, {atom(), any()}}
  def bind(_conn, _statement, _args), do: :erlang.nif_error(:not_loaded)

  @spec step(db(), statement()) :: :done | :busy | {:row, row()} | {:error, reason()}
  def step(_conn, _statement), do: :erlang.nif_error(:not_loaded)

  @spec multi_step(db(), statement(), integer()) ::
          :busy | {:rows, [row()]} | {:done, [row()]} | {:error, reason()}
  def multi_step(_conn, _statement, _chunk_size), do: :erlang.nif_error(:not_loaded)

  @spec columns(db(), statement()) :: {:ok, list(binary())} | {:error, reason()}
  def columns(_conn, _statement), do: :erlang.nif_error(:not_loaded)

  @spec last_insert_rowid(db()) :: {:ok, integer()}
  def last_insert_rowid(_conn), do: :erlang.nif_error(:not_loaded)

  @spec transaction_status(db()) :: {:ok, :idle | :transaction}
  def transaction_status(_conn), do: :erlang.nif_error(:not_loaded)

  @spec serialize(db(), String.Chars.t()) :: {:ok, binary()} | {:error, reason()}
  def serialize(_conn, _database), do: :erlang.nif_error(:not_loaded)

  @spec deserialize(db(), String.Chars.t(), binary()) :: :ok | {:error, reason()}
  def deserialize(_conn, _database, _serialized), do: :erlang.nif_error(:not_loaded)

  @spec release(db(), statement()) :: :ok | {:error, reason()}
  def release(_conn, _statement), do: :erlang.nif_error(:not_loaded)

  @spec enable_load_extension(db(), integer()) :: :ok | {:error, reason()}
  def enable_load_extension(_conn, _flag), do: :erlang.nif_error(:not_loaded)

  @spec set_update_hook(db(), pid()) :: :ok | {:error, reason()}
  def set_update_hook(_conn, _pid), do: :erlang.nif_error(:not_loaded)

  @spec set_log_hook(pid()) :: :ok | {:error, reason()}
  def set_log_hook(_pid), do: :erlang.nif_error(:not_loaded)

  # add statement inspection tooling https://sqlite.org/c3ref/expanded_sql.html
end
