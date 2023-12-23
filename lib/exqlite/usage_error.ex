defmodule Exqlite.UsageError do
  @moduledoc """
  Error resulting from the wrong usage of the library.

  Examples:

      iex> Exqlite.open(:not_a_path)
      {:error, %Exqlite.UsageError{message: "TODO"}}

  """

  defexception [:message]
  @type t :: %__MODULE__{message: String.t()}
end
