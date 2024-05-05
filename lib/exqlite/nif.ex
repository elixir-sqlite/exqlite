defmodule Exqlite.Nif do
  @moduledoc false

  @compile {:autoload, false}
  @on_load {:load_nif, 0}

  def load_nif do
    path = :filename.join(:code.priv_dir(:exqlite), ~c"sqlite3_nif")
    :erlang.load_nif(path, 0)
  end

  def open(_conn, _flags), do: :erlang.nif_error(:not_loaded)
  def close(_conn), do: :erlang.nif_error(:not_loaded)
  def execute(_conn, _sql), do: :erlang.nif_error(:not_loaded)
  def changes(_conn), do: :erlang.nif_error(:not_loaded)
  def prepare(_conn, _sql), do: :erlang.nif_error(:not_loaded)
  def bind(_conn, _stmt, _args), do: :erlang.nif_error(:not_loaded)
  def step(_conn, _stmt), do: :erlang.nif_error(:not_loaded)
  def multi_step(_conn, _stmt, _max_rows), do: :erlang.nif_error(:not_loaded)
  def multi_bind_step(_conn, _stmt, _rows), do: :erlang.nif_error(:not_loaded)
  def columns(_conn, _stmt), do: :erlang.nif_error(:not_loaded)
  def last_insert_rowid(_conn), do: :erlang.nif_error(:not_loaded)
  def transaction_status(_conn), do: :erlang.nif_error(:not_loaded)
  def serialize(_conn, _database), do: :erlang.nif_error(:not_loaded)
  def deserialize(_conn, _database, _serialized), do: :erlang.nif_error(:not_loaded)
  def release(_stmt), do: :erlang.nif_error(:not_loaded)
  def enable_load_extension(_conn, _flag), do: :erlang.nif_error(:not_loaded)
  def set_update_hook(_conn, _pid), do: :erlang.nif_error(:not_loaded)
  def set_log_hook(_pid), do: :erlang.nif_error(:not_loaded)
end
