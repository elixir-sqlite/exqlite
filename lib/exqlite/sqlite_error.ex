defmodule Exqlite.SQLiteError do
  @moduledoc """
  The error emitted from SQLite.
  """

  defexception [:message, :statement]

  @type t :: %__MODULE__{message: String.t(), statement: String.t()}

  @impl true
  def message(%__MODULE__{message: message, statement: nil}), do: message

  def message(%__MODULE__{message: message, statement: statement}) do
    "#{message}: #{statement}"
  end
end
