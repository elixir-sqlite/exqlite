defmodule Exqlite.Error do
  @moduledoc """
  Wraps an SQLite3 error.

  See: https://sqlite.org/rescode.html

  Examples:

      # SQLITE_MISUSE
      # https://sqlite.org/rescode.html#misuse
      %Exqlite.Error{code: 21, message: "TODO"}

      # SQLITE_BUSY
      # https://sqlite.org/rescode.html#busy
      %Exqlite.Error{code: 5, message: "TODO"}

  """
  @enforce_keys [:code, :message]
  defexception [:code, :message]
  @type t :: %__MODULE__{code: pos_integer, message: String.t()}
end
