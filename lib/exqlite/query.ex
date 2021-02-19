defmodule Exqlite.Query do
  @moduledoc """
  Query struct returned from a successfully prepared query.

  Its public fields are:

    * `name` - The name of the prepared statement;
    * `statement` - The prepared statement;
    * `columns` - The column names;
  """

  # IMPORTANT: This is closely modeled on Postgrex's query.ex file.
  # We strive to avoid structural differences between that file and this one.

  @type t :: %__MODULE__{
          name: iodata,
          statement: iodata,
          prepared: reference,
          columns: [String.t()] | nil,
          result_formats: [:binary | :text] | nil,
          types: Exqlite.TypeServer.table() | nil
        }

  defstruct [:name, :statement, :prepared, :columns, :result_formats, :types]

  defimpl DBConnection.Query do
    def parse(%{name: name} = query, _) do
      %{query | name: IO.iodata_to_binary(name)}
    end

    def describe(query, _), do: query

    def encode(_query, params, _opts), do: params
  end
end
