defmodule Exqlite.BindError do
  @moduledoc """
  An argument failed to bind.
  """

  defexception [:message, :argument]

  @type t :: %__MODULE__{
          message: String.t(),
          argument: term()
        }

  @impl true
  def message(%__MODULE__{message: message, argument: nil}), do: message

  def message(%__MODULE__{message: message, argument: argument}),
    do: "#{message} #{inspect(argument)}"
end
