defmodule Exqlite.SQLiteError do
  @moduledoc """
  The error emitted from SQLite.
  """

  defexception [:rc, :message]
  @type t :: %__MODULE__{rc: integer, message: String.t()}
end
