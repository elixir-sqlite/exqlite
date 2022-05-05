defmodule Exqlite.Error do
  @moduledoc false
  defexception [:message, :statement]

  @type t() :: %__MODULE__{
          message: String.t(),
          statement: String.t()
        }

  @impl true
  def message(%__MODULE__{message: message, statement: nil}), do: message

  def message(%__MODULE__{message: message, statement: statement}),
    do: "#{message}\n#{statement}"
end
