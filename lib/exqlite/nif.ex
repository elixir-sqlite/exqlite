defmodule Exqlite.Nif do
  @moduledoc false
  @compile {:autoload, false}
  @on_load {:load_nif, 0}

  def load_nif do
    path = :filename.join(:code.priv_dir(:exqlite), ~c"sqlite3_nif")
    :erlang.load_nif(path, 0)
  end

  # TODO individual binds

  def dirty_io_open(_path, _flags), do: :erlang.nif_error(:not_loaded)
  def dirty_io_close(_db), do: :erlang.nif_error(:not_loaded)
  def dirty_io_execute(_db, _sql), do: :erlang.nif_error(:not_loaded)
  def dirty_io_step(_db, _stmt), do: :erlang.nif_error(:not_loaded)
  def dirty_io_serialize(_db, _schema), do: :erlang.nif_error(:not_loaded)
  def dirty_io_deserialize(_db, _schema, _buffer), do: :erlang.nif_error(:not_loaded)
  def dirty_io_interrupt(_db), do: :erlang.nif_error(:not_loaded)

  def dirty_io_multi_step(_db, _stmt, _steps), do: :erlang.nif_error(:not_loaded)
  def dirty_io_insert_all(_db, _stmt, _rows), do: :erlang.nif_error(:not_loaded)

  def dirty_cpu_prepare(_db, _sql), do: :erlang.nif_error(:not_loaded)
  def dirty_cpu_bind_all(_db, _stmt, _params), do: :erlang.nif_error(:not_loaded)

  def execute(_db, _sql), do: :erlang.nif_error(:not_loaded)
  def changes(_db), do: :erlang.nif_error(:not_loaded)
  def prepare(_db, _sql), do: :erlang.nif_error(:not_loaded)
  def columns(_db, _stmt), do: :erlang.nif_error(:not_loaded)

  def step(_db, _stmt), do: :erlang.nif_error(:not_loaded)
  def interrupt(_db), do: :erlang.nif_error(:not_loaded)
  def finalize(_stmt), do: :erlang.nif_error(:not_loaded)
  def last_insert_rowid(_db), do: :erlang.nif_error(:not_loaded)
  def transaction_status(_db), do: :erlang.nif_error(:not_loaded)

  def bind_all(_db, _stmt, _params), do: :erlang.nif_error(:not_loaded)

  def enable_load_extension(_db, _path), do: :erlang.nif_error(:not_loaded)
  def set_update_hook(_db, _pid), do: :erlang.nif_error(:not_loaded)
  def set_log_hook(_pid), do: :erlang.nif_error(:not_loaded)
end
