defmodule Exqlite.Error do
  @moduledoc false
  defexception [:message, :statement]
end
